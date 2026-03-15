Process all pending questions in `questions/to-run/`.

For each question file:

1. Read the question
2. Research and write a thorough answer as a markdown file in `answers/` with a descriptive kebab-case filename (e.g., `best-api-for-weather-data.md`)
3. Move the question file from `questions/to-run/` to `questions/run/`

If there are no questions in `questions/to-run/`, inform the user.

After processing all questions, report a summary of what was answered.
