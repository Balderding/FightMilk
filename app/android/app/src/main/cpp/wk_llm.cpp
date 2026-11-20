// wk_llm: the app's small bridge to llama.cpp. Runs a model on the phone itself.
// One call = one chat turn: system + user -> answer, optionally locked to a grammar.
// Plain C API so Dart can call it through FFI. Licence: GPL-3.0 (this file), llama.cpp is MIT.
#include "llama.h"

#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#define WK_API extern "C" __declspec(dllexport)
#else
#define WK_API extern "C" __attribute__((visibility("default")))
#endif

struct wk_llm {
    llama_model *model = nullptr;
    llama_context *ctx = nullptr;
    int n_batch = 512;
};

static std::once_flag g_init;

static void quiet_log(ggml_log_level, const char *, void *) {}

static char *dup(const std::string &s) {
    char *p = (char *)std::malloc(s.size() + 1);
    if (p) std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

WK_API const char *wk_version() { return "wk_llm 1 / llama.cpp b12138"; }

// Loads a GGUF model. Returns null on failure (message in err).
WK_API wk_llm *wk_load(const char *path, int n_ctx, int n_threads, char *err, int errlen) {
    std::call_once(g_init, [] {
        llama_log_set(quiet_log, nullptr);
        llama_backend_init();
    });
    auto mp = llama_model_default_params();
    mp.n_gpu_layers = 0;  // CPU: works on every phone
    llama_model *model = llama_model_load_from_file(path, mp);
    if (!model) {
        if (err && errlen > 0) std::snprintf(err, errlen, "could not load the model file");
        return nullptr;
    }
    auto cp = llama_context_default_params();
    cp.n_ctx = n_ctx > 0 ? n_ctx : 4096;
    cp.n_batch = 512;
    cp.n_threads = n_threads > 0 ? n_threads : 4;
    cp.n_threads_batch = cp.n_threads;
    llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx) {
        llama_model_free(model);
        if (err && errlen > 0) std::snprintf(err, errlen, "not enough memory for the model");
        return nullptr;
    }
    auto *h = new wk_llm();
    h->model = model;
    h->ctx = ctx;
    h->n_batch = (int)cp.n_batch;
    return h;
}

WK_API void wk_unload(wk_llm *h) {
    if (!h) return;
    if (h->ctx) llama_free(h->ctx);
    if (h->model) llama_model_free(h->model);
    delete h;
}

WK_API void wk_free_str(char *s) { std::free(s); }

// status: 0 ok, 1 prompt too long, 2 model error, 3 bad grammar, 4 stopped at max_tokens (text still returned)
WK_API char *wk_chat(wk_llm *h, const char *system, const char *user, const char *grammar, int max_tokens, float temp, unsigned seed, int *status) {
    *status = 2;
    if (!h) return dup("");
    const llama_vocab *vocab = llama_model_get_vocab(h->model);

    // ChatML, which LFM uses
    std::string prompt;
    if (system && *system) prompt += std::string("<|im_start|>system\n") + system + "<|im_end|>\n";
    prompt += std::string("<|im_start|>user\n") + user + "<|im_end|>\n<|im_start|>assistant\n";

    int n = -llama_tokenize(vocab, prompt.c_str(), (int)prompt.size(), nullptr, 0, true, true);
    std::vector<llama_token> toks(n > 0 ? n : 0);
    if (n <= 0 || llama_tokenize(vocab, prompt.c_str(), (int)prompt.size(), toks.data(), n, true, true) < 0) return dup("");
    const int n_ctx = (int)llama_n_ctx(h->ctx);
    if ((int)toks.size() + 8 >= n_ctx) {
        *status = 1;
        return dup("");
    }

    llama_memory_clear(llama_get_memory(h->ctx), true);
    for (size_t i = 0; i < toks.size(); i += h->n_batch) {
        int m = (int)std::min<size_t>(h->n_batch, toks.size() - i);
        if (llama_decode(h->ctx, llama_batch_get_one(toks.data() + i, m)) != 0) return dup("");
    }

    auto sp = llama_sampler_chain_default_params();
    llama_sampler *smpl = llama_sampler_chain_init(sp);
    if (grammar && *grammar) {
        llama_sampler *g = llama_sampler_init_grammar(vocab, grammar, "root");
        if (!g) {
            llama_sampler_free(smpl);
            *status = 3;
            return dup("");
        }
        llama_sampler_chain_add(smpl, g);
    }
    llama_sampler_chain_add(smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(smpl, llama_sampler_init_temp(temp));
    llama_sampler_chain_add(smpl, llama_sampler_init_dist(seed));

    std::string out;
    int used = (int)toks.size();
    int st = 0;
    char buf[256];
    for (int i = 0; i < max_tokens; i++) {
        llama_token t = llama_sampler_sample(smpl, h->ctx, -1);
        if (llama_vocab_is_eog(vocab, t)) break;
        int k = llama_token_to_piece(vocab, t, buf, sizeof buf, 0, false);
        if (k > 0) out.append(buf, k);
        if (++used >= n_ctx - 1) {
            st = 4;
            break;
        }
        if (llama_decode(h->ctx, llama_batch_get_one(&t, 1)) != 0) {
            st = 2;
            break;
        }
        if (i == max_tokens - 1) st = 4;
    }
    llama_sampler_free(smpl);
    *status = st;
    return dup(out);
}
