# Run MLX's Python test suite, minus tests that exceed the limits of the
# virtualised M1 GPUs on the CI runners rather than test the package.
import sys
import unittest

SKIP = {
    # Allocates one 4 GiB Metal buffer; the runners cap a buffer at 3.5 GiB.
    "test_reduce.TestReduce.test_init_reduce_large_output",
    # The D=512 sdpa_vector kernels request 1024 threads per threadgroup, but
    # their pipelines allow only 640-832 on M1/M2. Upstream bug, cf.
    # https://github.com/ml-explore/mlx/issues/4718
    "test_fast_sdpa.TestFastSDPA.test_sdpa_vector_head_dim_512",
}


def without_skipped(suite):
    kept = unittest.TestSuite()
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            kept.addTest(without_skipped(test))
        elif test.id() in SKIP:
            print(f"skipping {test.id()}")
        else:
            kept.addTest(test)
    return kept


suite = unittest.defaultTestLoader.discover(sys.argv[1])
result = unittest.TextTestRunner(verbosity=1).run(without_skipped(suite))
sys.exit(not result.wasSuccessful())
