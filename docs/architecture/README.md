# SignZero architecture diagrams

Architecture diagrams for SignZero. Keep each diagram in its own file, named for what it shows (for example
`signing-flow.md`, `data-model.png`).

- Prefer [Mermaid](https://mermaid.js.org/) in Markdown (`.md`): it is text, so changes show up in code review, and
  GitHub and VS Code render it.
- Exported images (`.png`, `.svg`) are fine for diagrams drawn in other tools. Keep the editable source (for example
  a `.drawio` file) next to the export.

| Diagram | Shows |
|---|---|
| [signing-flow.md](signing-flow.md) | Sending, signing and sealing an envelope, and where the PDF work runs |
