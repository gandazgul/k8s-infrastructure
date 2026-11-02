#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

// Integer-valued FP32 inputs keep the reference exactly representable: no
// tolerance can conceal a broken kernel, a no-op launch, or stale output.
constexpr int width = 32;
constexpr int elements = width * width;

static void check(cudaError_t status, const char *operation) {
    if (status != cudaSuccess) {
        throw std::runtime_error(std::string(operation) + ": " + cudaGetErrorString(status));
    }
}

__global__ void matrixProduct(const float *a, const float *b, float *out, int *compiledArch) {
#if !defined(__CUDA_ARCH__) || __CUDA_ARCH__ == 750
    const int row = blockIdx.y * blockDim.y + threadIdx.y;
    const int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (row < width && col < width) {
        float value = 0;
        for (int k = 0; k < width; ++k) {
            value += a[row * width + k] * b[k * width + col];
        }
        out[row * width + col] = value;
        if (row == 0 && col == 0) {
#ifdef __CUDA_ARCH__
            *compiledArch = __CUDA_ARCH__;
#endif
        }
    }
#else
#error "This benchmark gate must contain SM75 device code only"
#endif
}

int main() {
    float *deviceA = nullptr, *deviceB = nullptr, *deviceOut = nullptr;
    int *deviceArch = nullptr;
    try {
        int devices = 0;
        check(cudaGetDeviceCount(&devices), "cudaGetDeviceCount");
        if (devices != 1) {
            throw std::runtime_error("expected exactly one visible CUDA device");
        }
        check(cudaSetDevice(0), "cudaSetDevice");
        cudaDeviceProp properties{};
        check(cudaGetDeviceProperties(&properties, 0), "cudaGetDeviceProperties");
        if (properties.major != 7 || properties.minor != 5) {
            throw std::runtime_error("expected compute capability 7.5");
        }

        std::vector<float> a(elements), b(elements), actual(elements), reference(elements, 0);
        for (int i = 0; i < elements; ++i) {
            a[i] = static_cast<float>((i * 7 + 3) % 31 - 15);
            b[i] = static_cast<float>((i * 11 + 5) % 29 - 14);
        }
        for (int row = 0; row < width; ++row) {
            for (int col = 0; col < width; ++col) {
                for (int k = 0; k < width; ++k) {
                    reference[row * width + col] += a[row * width + k] * b[k * width + col];
                }
            }
        }

        const size_t bytes = elements * sizeof(float);
        check(cudaMalloc(reinterpret_cast<void **>(&deviceA), bytes), "cudaMalloc A");
        check(cudaMalloc(reinterpret_cast<void **>(&deviceB), bytes), "cudaMalloc B");
        check(cudaMalloc(reinterpret_cast<void **>(&deviceOut), bytes), "cudaMalloc output");
        check(cudaMalloc(reinterpret_cast<void **>(&deviceArch), sizeof(int)), "cudaMalloc architecture");
        check(cudaMemcpy(deviceA, a.data(), bytes, cudaMemcpyHostToDevice), "copy A");
        check(cudaMemcpy(deviceB, b.data(), bytes, cudaMemcpyHostToDevice), "copy B");
        check(cudaMemset(deviceOut, 0xff, bytes), "poison output with NaNs");
        check(cudaMemset(deviceArch, 0, sizeof(int)), "clear architecture");
        matrixProduct<<<dim3(4, 4), dim3(8, 8)>>>(deviceA, deviceB, deviceOut, deviceArch);
        check(cudaGetLastError(), "matrixProduct launch");
        check(cudaDeviceSynchronize(), "matrixProduct execution");
        check(cudaMemcpy(actual.data(), deviceOut, bytes, cudaMemcpyDeviceToHost), "copy results");
        int compiledArch = 0;
        check(cudaMemcpy(&compiledArch, deviceArch, sizeof(int), cudaMemcpyDeviceToHost), "copy architecture");
        if (compiledArch != 750) {
            throw std::runtime_error("executed kernel did not report SM75");
        }
        for (int i = 0; i < elements; ++i) {
            if (!std::isfinite(actual[i]) || actual[i] != reference[i]) {
                throw std::runtime_error("matrix result mismatch at element " + std::to_string(i));
            }
        }
        check(cudaFree(deviceA), "cudaFree A"); deviceA = nullptr;
        check(cudaFree(deviceB), "cudaFree B"); deviceB = nullptr;
        check(cudaFree(deviceOut), "cudaFree output"); deviceOut = nullptr;
        check(cudaFree(deviceArch), "cudaFree architecture"); deviceArch = nullptr;
        check(cudaDeviceReset(), "cudaDeviceReset");
        std::puts("{\"status\":\"pass\",\"device_count\":1,\"compute_capability\":\"7.5\",\"kernel_arch\":750,\"validated_fp32_outputs\":1024}");
        return 0;
    } catch (const std::exception &error) {
        // No user content or credentials enter this program.
        std::fprintf(stderr, "CUDA_GATE_FAIL: %s\n", error.what());
        if (deviceA) cudaFree(deviceA);
        if (deviceB) cudaFree(deviceB);
        if (deviceOut) cudaFree(deviceOut);
        if (deviceArch) cudaFree(deviceArch);
        cudaDeviceReset();
        return 1;
    }
}
