# Windows Installer Draft

This project now separates installation files from writable user data.

- App binaries install to the folder chosen in the installer.
- Live data stays in `%LOCALAPPDATA%\PMIS DepED\`.
- The SQLite database path is `%LOCALAPPDATA%\PMIS DepED\pmis_deped.db`.
- Backups and archives live in `%LOCALAPPDATA%\PMIS DepED\archives\`.

## Build the apps

From the repo root:

```powershell
flutter build windows --release
cd password_reset_utility
flutter pub get
flutter build windows --release
```

The release outputs used by the installer are:

```text
build\windows\x64\runner\Release\
password_reset_utility\build\windows\x64\runner\Release\
```

## Build the installer

1. Install Inno Setup 6.
2. Open `installer\pmis_deped.iss` in the Inno Setup Compiler.
3. Update `MyAppVersion` before each production release.
4. Compile the script.

The generated installer will be written to:

```text
installer\output\
```

## Installer behavior

- The installer shows the install directory page.
- The installer shows the Start Menu folder page.
- The installer offers an optional desktop shortcut checkbox.
- The installer excludes any local `.db` files and `archives\` content from the package.
- If the password reset utility has been built, the installer also packages it as a separate executable and Start Menu shortcut.

## Optional adjustment

The current draft installs to `Program Files` and therefore expects admin rights.

If you want a no-admin per-user installer instead, change this line in `installer\pmis_deped.iss`:

```text
DefaultDirName={autopf64}\PMIS DepED
```

to:

```text
DefaultDirName={localappdata}\Programs\PMIS DepED
```

and set:

```text
PrivilegesRequired=lowest
```
