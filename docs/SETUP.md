# Setup on Windows: cloud build and TestFlight

## Free option: sideload the IPA (no $99 account)

1. Do step 2 below (GitHub Desktop, rename `_github` to `.github`, publish).
2. On github.com: **Actions > Sideload IPA > Run workflow**. When it's green, open the run and download **OxydeMap-ipa** (a zip with `OxydeMap.ipa` inside). Unzip it.
3. Install **iTunes** (from apple.com, not the Microsoft Store version) and **Sideloadly** (sideloadly.io) on the PC.
4. Connect the iPhone by USB and tap **Trust**. In Sideloadly, drag in `OxydeMap.ipa`, enter your Apple ID, and click **Start**.
5. On the iPhone: **Settings > General > VPN & Device Management**, trust your Apple ID. Then **Settings > Privacy & Security > Developer Mode** on (the phone restarts).

Limits of a free Apple ID: the app stops opening after 7 days until you sideload it again, CarPlay and iCloud sync can't be enabled, and Premium purchases won't load. Maps, search, navigation, voice, Map Studio and trips all work.

The rest of this page is the paid route, which gives TestFlight installs that last 90 days and enables CarPlay later.

You don't need a Mac. GitHub's cloud Macs compile and test the app. The signed build then goes to TestFlight, and you install it on your iPhone from there.

Total time the first time: about an hour of clicking, plus Apple's review of your developer enrollment (often a day or two).

## 1. Join the Apple Developer Program

1. On your iPhone or PC, go to <https://developer.apple.com/programs/enroll/> and sign in with your Apple ID.
2. Enroll as an **Individual** ($99 per year). Apple confirms by email.
3. When it's active, open <https://developer.apple.com/account> and note your **Team ID** (10 characters, under Membership details).

## 2. Put the code on GitHub

1. Create a free account at <https://github.com> if you don't have one.
2. Install **GitHub Desktop** for Windows: <https://desktop.github.com>.
3. Move the build workflows into place. They were delivered as `G:\ox map\_github` because the `.github` folder can't be written remotely. In PowerShell:

   ```powershell
   Rename-Item "G:\ox map\_github" ".github"
   ```

   Without this step, GitHub won't run any cloud builds.
4. In GitHub Desktop: **File > Add local repository**, choose `G:\ox map`. It offers to create a repository there; accept.
5. Commit everything (the summary can be "First version"), then **Publish repository**. Keep **Private** ticked if you want the code private.

> GitHub gives private repositories a limited number of macOS build minutes each month (macOS minutes count 10x). A public repository builds for free. Each CI run takes roughly 10 to 20 minutes.

6. On github.com, open your repository and click **Actions**. The **CI** workflow starts on its own after each push. Wait for it to finish:
   - Green: the app compiles and the tests pass on a real iOS simulator.
   - Red: open the failed step and copy the error. Paste it into the project chat and Claude will fix it.

The first CI run is the first time this app is compiled for iOS, so expect to fix a few compile errors.

## 3. Create the app in App Store Connect

1. Go to <https://developer.apple.com/account/resources/identifiers/list>, click **+**, choose **App IDs > App**.
   - Description: `Oxyde Map`
   - Bundle ID (explicit): something like `com.yourname.oxydemap`
   - Capabilities: leave the defaults for now. CarPlay comes later (docs/CARPLAY.md).
2. Go to <https://appstoreconnect.apple.com>, **Apps > + > New App**.
   - Platform iOS, name `Oxyde Map` (if taken, add a word), language, the bundle ID from step 1, and an SKU such as `oxydemap1`.

## 4. Create an API key and add GitHub secrets

1. In App Store Connect: **Users and Access > Integrations > App Store Connect API > Team Keys**. Request access if asked, then **+**.
   - Name: `GitHub`, Access: **Admin**. Admin lets the cloud Mac create signing certificates and profiles for you.
2. Download the `.p8` file (you can only download it once) and note the **Key ID** and the **Issuer ID** shown above the list.
3. Convert the key to text. In Windows, open **PowerShell** in the folder with the file and run:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXXXXXX.p8")) | Set-Clipboard
   ```

   The text is now on your clipboard.
4. On GitHub: your repository > **Settings > Secrets and variables > Actions > New repository secret**. Add:

   | Name | Value |
   |---|---|
   | `APPLE_TEAM_ID` | Team ID from step 1 |
   | `APP_BUNDLE_ID` | The bundle ID from step 3 |
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8_BASE64` | Paste the clipboard |
   | `OX_BACKEND_BASE_URL` | Optional, once your backend runs (docs/BACKEND.md) |

5. Delete the `.p8` from your Downloads folder once it's saved somewhere safe, such as a password manager.

## 5. Build for TestFlight

1. GitHub > **Actions > TestFlight > Run workflow**.
2. When it's green, Apple processes the build for 10 to 30 minutes. You get an email.
3. In App Store Connect: your app > **TestFlight**. Answer the export compliance question if it appears (the app uses only standard HTTPS, so choose "None of the algorithms mentioned above").
4. Under **Internal Testing**, create a group, add yourself, and add the build.

## 6. Install on your iPhone

1. Install **TestFlight** from the App Store on your iPhone 14.
2. Open the invitation email on the iPhone, or open TestFlight; Oxyde Map appears there. Tap **Install**.
3. Each time you run the TestFlight workflow again, TestFlight offers the update.

## 7. Optional extras

- **Traffic incidents and driver reports** need the backend running: docs/BACKEND.md. Without it, the app says so in Settings > Diagnostics and hides reporting.
- **CarPlay in your car** needs Apple's entitlement: docs/CARPLAY.md. Until then, CarPlay can only be tried in the CarPlay Simulator on a Mac.
- **Premium purchases** need the three products created in App Store Connect: docs/APP_STORE.md. TestFlight purchases are free sandbox purchases.

## Working on the code later

- Edit files in `G:\ox map` with any editor (VS Code works well), commit and push with GitHub Desktop, and CI checks the change.
- Don't edit `OxydeMap.xcodeproj` by hand. The workflows regenerate it from `project.yml`. Add new Swift files inside `OxydeMap/` and they are picked up automatically.
- Your own values (bundle ID, backend URL) go in `Config/Secrets.xcconfig`, copied from `Config/Secrets.example.xcconfig`. That file is never committed; the workflows write it from your GitHub secrets.

## If you get a Mac later

```
brew install xcodegen
xcodegen generate
open OxydeMap.xcodeproj
```

Pick the **OxydeMap** scheme and an iPhone simulator, then Run. The scheme uses `OxydeMap.storekit`, so purchases can be tested locally. **I/O > External Displays > CarPlay** in the simulator shows the CarPlay screen.
