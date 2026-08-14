import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULTS = (ROOT / "firmware" / "sdkconfig.defaults").read_text()
TRANSPORT = (
    ROOT / "firmware" / "components" / "transport" / "mac_transport.c"
).read_text()


class OTAMemorySourceTests(unittest.TestCase):
    def test_release_avoids_transient_internal_aes_dma_allocations(self):
        self.assertIn("# CONFIG_MBEDTLS_HARDWARE_AES is not set", DEFAULTS)
        self.assertIn("CONFIG_MBEDTLS_EXTERNAL_MEM_ALLOC=y", DEFAULTS)

    def test_wifi_recovery_does_not_reserve_an_extra_task_stack(self):
        self.assertIn("esp_timer_create", TRANSPORT)
        self.assertNotIn('xTaskCreate(wifi_recovery_task', TRANSPORT)


if __name__ == "__main__":
    unittest.main()
