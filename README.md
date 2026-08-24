# ChartScout

Native macOS chart-analysis assistant for Chrome. Press **Command–Shift–Space** while Chrome is frontmost to capture its current chart, confirm the detected contract/timeframe, and receive an advisory-only trade setup beside the cursor.

## Run

Open this folder in Xcode and run the `ChartScout` scheme, or use:

```sh
swift run ChartScout
```

On first use, allow Screen Recording and Accessibility in **System Settings → Privacy & Security**. In ChartScout Settings, enter an OpenAI API key (stored in Keychain) and model name.

## Analysis response format

ChartScout requests strict OpenAI Structured Outputs for both chart metadata and trade recommendations. The supplied JSON schemas require every field used by the app, constrain recommendation values such as bias and confidence, and require at least one key level. This prevents valid-but-incompatible JSON from being treated as a usable recommendation.

Trade analysis follows a conditional market-structure workflow: it prioritizes visible liquidity and location, requires confirmation before presenting an active setup, reduces confidence in ambiguous conditions, and names the condition that invalidates the thesis.

Response failures are reported by category. The app distinguishes HTTP and model errors, refusals, output-limit truncation, empty responses, and JSON decoding failures instead of displaying the same generic “response incomplete” message for every condition.

This software is for informational chart analysis only. It can misread chart visuals and does not place orders or provide financial advice.
