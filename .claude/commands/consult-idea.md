---
description: Ask Codex for a second opinion on an idea
allowed-tools: bash
---

# Consult Codex on an Idea

You've been discussing an idea or proposal with the user. Now you'll ask Codex for a second opinion, then bring back and assess its feedback.

## Step 1: Summarize the Idea

Look back at the conversation and extract the idea or proposal that was just discussed. Write a clear, self-contained summary that includes:
- What the idea is about
- The problem it's trying to solve
- The proposed approach or solution
- Any constraints, trade-offs, or open questions that came up
- Any decisions that were already made

The summary must be self-contained — Codex has no access to this conversation, so it needs all the relevant context in the prompt.

## Step 2: Ask Codex for Its Opinion

Run the following command, replacing `<IDEA_SUMMARY>` with the summary you wrote in Step 1:

```bash
codex exec --full-auto "<IDEA_SUMMARY>

Now that you understand the idea, give me your honest opinion as a senior engineer:

1. Does this approach make sense? Is the reasoning sound?
2. What are the biggest risks or blind spots?
3. Is there a simpler way to achieve the same goal?
4. What would you do differently?
5. Are there edge cases or failure modes that haven't been considered?
6. Is anything over-engineered or unnecessary?

Be direct and constructive. We want a pragmatic assessment — is this idea GOOD ENOUGH to move forward with, or are there fundamental issues that need to be rethought? We are not looking for perfection."
```

## Step 3: Assess Codex's Feedback

Once Codex responds, go through its feedback and categorize it:

### Worth Considering
Points that are valid, actionable, and could genuinely improve the idea or prevent problems.

### Disagree / Not Applicable
Points where you think Codex is wrong, lacks context, or is raising theoretical concerns that don't apply here.

## Step 4: Report Back

Present the results to the user:

### Codex's Opinion
Summarize the key points from Codex's feedback.

### My Take
For each point, explain whether you agree or disagree and why. Add your own perspective where relevant.

### Suggested Adjustments
If any of the feedback warrants changes to the idea, list them as concrete suggestions.

Then ask the user how they'd like to proceed.
