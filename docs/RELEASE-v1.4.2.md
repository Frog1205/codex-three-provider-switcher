# v1.4.2 Windows field help

Display version: `V_1.4_261026.02`.

The custom API editor explains all eight fields next to their controls: saved routes, display name, unique ID, API base URL, actual model ID, optional environment variable name, API key, and protocol. The fields scroll within the existing window size while testing, saving, switching and closing remain in a fixed footer.

Base URL help uses `https://api.example.com/v1` strictly as an example. Users must copy the provider's actual base URL, including any documented path prefix. A live preview shows the exact request address for the selected protocol. Preview and connection tests share the same endpoint builder.

The endpoint builder accepts HTTP(S) URLs, preserves custom prefixes and local ports, trims trailing slashes, and appends `/responses` or `/chat/completions`. It rejects complete endpoint URLs to avoid duplicate suffixes, and rejects embedded credentials, query parameters and fragments. It never forces `/v1` onto a provider URL.

Regression covers root URLs, local ports, custom prefixes, suffix selection, invalid base URLs, exact preview/request agreement, all field descriptions, scrolling and fixed actions, plus the existing credential and configuration tests. HTTP requests use mock fixtures. Installation and portable package validation remain required before publication. No live provider availability is inferred from these tests.

Windows packages remain unsigned. macOS stays on v1.3.
