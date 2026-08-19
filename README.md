# ChartScout

Native macOS chart-analysis assistant for Chrome. Press **Command–Shift–Space** while Chrome is frontmost to capture its current chart, confirm the detected contract/timeframe, and receive an advisory-only trade setup beside the cursor.

## Run

Open this folder in Xcode and run the `ChartScout` scheme, or use:

```sh
swift run ChartScout
```

On first use, allow Screen Recording and Accessibility in **System Settings → Privacy & Security**. In ChartScout Settings, enter an OpenAI API key (stored in Keychain) and model name. The default is `gpt-4.1-mini`.

This software is for informational chart analysis only. It can misread chart visuals and does not place orders or provide financial advice.
