---
description: Ask Codex to code review your changes
allowed-tools: bash
---

# Ask Codex for Code Review

You've just made code changes. Now you'll ask the Codex agent to review them, then assess and act on its feedback.

This command is designed for the v0.1 workflow:
- changes remain uncommitted in the working tree
- review the current diff, not a branch-based commit range

## Step 1: Gather Context

- Run `git diff` to confirm there are uncommitted changes to review
- If there are no changes, inform the user and stop

## Step 2: Ask Codex for a Code Review

Run the following command to get Codex's review of the uncommitted changes:

```bash
codex review --uncommitted "Focus your review on: 1. Are there bugs or logic errors? 2. Is this the simplest approach, or is it over-engineered? 3. Is there code that was added but is not actually needed? 4. Is there code that was modified unnecessarily? 5. Are there any security issues? 6. Is anything missing that should have been implemented? IMPORTANT: We are looking for code that is GOOD ENOUGH for production, not perfect. Do not flag minor style issues, nitpicks, or theoretical concerns. Only flag issues that a senior developer would consider worth fixing before merging. For each finding include the file, what the issue is, why it matters, and a suggested fix. End with a clear verdict: Is this code good enough for production?"
```

## Step 3: Assess Codex's Feedback

Once Codex responds, carefully go through each finding and categorize it:

### Must Fix
Issues that are genuine problems—bugs, security holes, missing functionality, or code that would cause real trouble in production. These need to be addressed.

### Skip
Nitpicks, style preferences, or theoretical concerns that don't affect production readiness. Ignore these—we're not chasing perfection.

## Step 4: Report and Act

Present your assessment to the user:

### Codex Said
Summarize the key points from Codex's review.

### My Assessment
For each finding, explain whether you agree or disagree and why.

### Action Plan
List the changes you intend to make based on the findings that actually matter.

Then ask the user: "Should I go ahead and apply these fixes?"

If the user agrees, make the changes.
