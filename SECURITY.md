# Security policy

MACZONE is a preview release. If you find a security issue, please avoid posting exploit details in a public issue. Use GitHub's **Report a vulnerability** option under this repository's Security tab to send a private report to the maintainer.

The app manages windows through macOS accessibility APIs and stores its layout library locally at `~/Library/Application Support/MACZONE/library.json`. The Alfred workflow sends commands to the installed app through the local `maczone://` URL scheme.
