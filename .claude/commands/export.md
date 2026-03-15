Generate a consolidated PDF export of all questions and answers using Typst.

Steps:

1. Read all answered questions from `questions/run/` and their corresponding answers from `answers/` (including subfolders)
2. Create or update `exports/template.typ` with a Typst template that includes:
   - Title page with "AI-Native Backend Notes" and generation date
   - Page numbers in the footer
   - Generation date in dd/mm/yyyy format in the footer
   - Clean typography for questions (summarised) followed by full answers
3. Generate `exports/content.typ` with the actual Q&A content using the template
4. Compile with `typst compile exports/content.typ exports/export-DDMMYYYY.pdf`

Ensure the `exports/` directory exists before writing.
