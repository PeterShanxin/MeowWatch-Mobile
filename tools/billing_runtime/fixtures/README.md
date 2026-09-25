# Android dialog regression fixtures

`api35_test_store_dialog.xml` is the native accessibility snapshot from GitHub
Actions run [35056405179](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35056405179),
artifact run `20260916T044622Z-76be27b8`, captured at its cancelled-purchase
automation timeout. The actual 1080 x 2400 Android screenshot showed the correct
Test Store title, product and three buttons. No purchase click had occurred.
The fixture contains only this generic Test Store dialog, with no customer ID,
API key, receipt, or account details.

`api35_windows_without_focus.txt` is a reduced excerpt of that run's
`cancel-failure-window.txt`. The full `dumpsys window windows` output contained
visible MeowWatch windows and IME targets but **no `mCurrentFocus` field**.
Neither window visibility nor IME ownership is adequate proof of input focus.

The regression tests must continue rejecting this focus-less excerpt. They also
check that the adb observation requests `dumpsys window displays`, where Android
`DisplayContent.dump` emits `mCurrentFocus`. The positive focus response in the
command-boundary test is an explicit test double for that documented Android
contract, not a newly captured device result. The next CI run must verify the
corrected query and purchase outcomes on the actual emulator.
