import unittest
from pathlib import Path

from tools.nearby_runtime.run import drive_command, validate_result


class NearbyRuntimeRunnerTest(unittest.TestCase):
    def test_drive_keeps_same_install_running_until_owned_force_stop(self) -> None:
        command = drive_command("emulator-5554", Path("app-debug.apk"), 2)
        self.assertIn("--keep-app-running", command)
        self.assertIn("--use-application-binary=app-debug.apk", command)
        self.assertNotIn("--no-keep-app-running", command)
        self.assertEqual(command[-2:], ["-d", "emulator-5554"])

    def test_result_requires_matching_completed_stage(self) -> None:
        nearby = validate_result(
            {"nearbyRuntime": {"stage": 3, "completed": True}},
            3,
        )
        self.assertEqual(nearby["stage"], 3)
        with self.assertRaises(ValueError):
            validate_result(
                {"nearbyRuntime": {"stage": 2, "completed": True}},
                3,
            )

    def test_result_rejects_secret_bearing_evidence(self) -> None:
        with self.assertRaises(ValueError):
            validate_result(
                {
                    "nearbyRuntime": {
                        "stage": 1,
                        "completed": True,
                        "tokenId": "must-not-be-written",
                    }
                },
                1,
            )

    def test_boolean_evidence_boundaries_do_not_expose_secret_values(self) -> None:
        nearby = validate_result(
            {
                "nearbyRuntime": {
                    "stage": 1,
                    "completed": True,
                    "rawSecretsReported": False,
                    "privateAddressesLogged": False,
                }
            },
            1,
        )
        self.assertFalse(nearby["rawSecretsReported"])
        with self.assertRaises(ValueError):
            validate_result(
                {
                    "nearbyRuntime": {
                        "stage": 1,
                        "completed": True,
                        "value": "-----BEGIN PRIVATE KEY-----",
                    }
                },
                1,
            )


if __name__ == "__main__":
    unittest.main()
