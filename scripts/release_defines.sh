# Sourced by .github/workflows/release.yml before `flutter build`: turns the build settings in the environment
# (SERVER_URL, APP_KEY, ...) into a `defines` array of --dart-define flags, and stops a release that would ship
# the app key in the clear.

# The app key is sent with every request, so refuse to build it with a server address that would send it in the
# clear (the app ignores such an address too, but a release should fail loudly instead).
if [ -n "${SERVER_URL:-}" ] && ! [[ "$SERVER_URL" =~ ^https://[^/[:space:]]+ ]]; then
  echo "::error::The SERVER_URL variable must start with https:// (it is '$SERVER_URL')"
  exit 1
fi
if [ -z "${SERVER_URL:-}" ]; then
  echo "::warning::SERVER_URL is not set, so this build will only look for a server on the local network. Fine for a test; set it for a public release."
elif [ -z "${APP_KEY:-}" ]; then
  echo "::warning::SERVER_URL is set but the APP_KEY secret is not, so the server will refuse every request if it has a key."
fi

defines=()
# An empty --dart-define would replace the default with "", so only pass the ones that are set.
for name in PRIVACY_POLICY_URL TERMS_OF_SERVICE_URL SUPPORT_EMAIL SERVER_URL APP_KEY TALK_MODE UPDATE_FEED; do
  if [ -n "${!name:-}" ]; then defines+=("--dart-define=$name=${!name}"); fi
done
