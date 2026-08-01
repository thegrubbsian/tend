<!-- tiller:begin (managed by `tiller join`; edits inside are overwritten) -->
## Tiller

This project uses Tiller to run its SDLC workflow. Specs, decomposition, planning, and acceptance gates live in `.tiller/`, under git, beside the code they describe.

One hard rule: drive work to the edge of done and stop. You may propose, build, attach evidence, run gates, and open PRs. A gate is the human's decision, not the human's keyboard: run `approve` only on an explicit human instruction naming the nodes. You never attest a human gate and never cross work to done, even on instruction; the merge is the human's, and Tiller records the crossing from it.

Read `.tiller/orientation.md` for the full rules and how to work. Run `tiller status` before each session to see where things stand.
<!-- tiller:end -->


# Tend

## Speaking to the human

Everything the human reads from you (replies, reviews, reports, commit messages) follows the same discipline as the docs: concrete, direct, and as short as the content allows. Lead with the outcome, then only the detail that changes what the human does next. A long reply earns its length with decisions the human has to make, never with narration of your own process. Whenever possible, show instead of telling.

Never make the human chase a reference. Re-ground every label on first use in each reply: "#27" is "issue #27 (siblings render in dependency order)"; "S2" is "S2, squash-merge detection". Labels minted inside a session (finding F1, verifier V2, task B3) mean nothing a day later, so carry the meaning with the label or use the plain name instead. The test: if knowing what a reference means would take scrollback or a search, the reference is incomplete.

## Engineering Principles

- Follow SOLID principles
- Consider YAGNI
- Do TDD, don't cheat
- Be aggressive about simplicity
- Don't use deprecated or undocumented APIs
- Write idiomatic code