---
description: Review your own work for improvements
---

# Self-Review Your Work

Now that you have written the code, take a step back and critically evaluate your own work. Pretend you're reviewing someone else's code with fresh eyes.

## Step 1: Review What You Wrote

Go through all the changes you made in this session:
- Run `git diff` to see the uncommitted changes
- Re-read the code you wrote or modified
- Look at each file you touched

## Step 2: Ask Yourself These Questions

### Could this be simpler?
- Is there a more straightforward way to achieve the same result?
- Did you over-engineer or add unnecessary abstraction?
- Are there complex patterns that could be replaced with simpler ones?
- Could any functions be shorter or more focused?

### Is there code that's no longer needed?
- Did you write helper functions that ended up unused?
- Are there variables, imports, or constants that aren't being used?
- Did you leave any debug statements, console logs, or commented code?
- Did earlier iterations leave behind dead code?

### Can anything be cleaned up?
- Are there inconsistent naming conventions?
- Is there duplicated code that could be consolidated?
- Are there magic numbers or strings that should be constants?
- Could the code be better organized or structured?

### Is anything missing?
- Look back at the original task or implementation plan
- Did you implement everything that was requested?
- Are there edge cases you discussed but didn't handle?
- Did you skip any error handling or validation?
- Are there TODOs you left that should be addressed now?

## Step 3: Report Your Findings

Provide an honest assessment:

### Things I Would Improve
List specific changes you'd make, with file names and descriptions.

### Code to Remove
Any unnecessary code you spotted that should be deleted.

### Missing Pieces
Anything from the original plan that still needs to be implemented.

### Overall Assessment
Is the code in a good state, or does it need more work before it's ready?

---

After this review, ask if the user wants you to make any of the identified improvements.
