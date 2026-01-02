# Constraints & Conditions

This document defines the boundaries and limitations for project development.

---

## Content Constraints

### DO NOT Include

- ❌ Real company names or internal references
- ❌ Production domain names, IPs, or URLs
- ❌ Secrets, tokens, API keys, or credentials
- ❌ Proprietary workflows or configurations
- ❌ Client/customer data or identifiers
- ❌ Internal repository names or account IDs

### ALWAYS Use

- ✅ Generic placeholders (`example.com`, `my-company`)
- ✅ Synthetic/anonymized examples
- ✅ Public vendor names (AWS, GCP, GitHub, etc.)
- ✅ Standard open-source tools and patterns

---

## Code Constraints

### DO NOT

- ❌ Introduce security vulnerabilities
- ❌ Add unnecessary complexity or over-engineering
- ❌ Create "clever" solutions when simple ones work
- ❌ Add features beyond scope
- ❌ Modify files outside of scope

### DO

- ✅ Follow existing code style and conventions
- ✅ Use idiomatic patterns for the language/tool
- ✅ Keep solutions minimal and focused
- ✅ Document non-obvious decisions

---

## Git Constraints

### DO NOT

- ❌ Include AI attribution (Co-Authored-By, Generated with Claude)
- ❌ Force push to shared branches (unless cleaning AI attribution)
- ❌ Commit large binary files
- ❌ Commit sensitive configuration files

### DO

- ✅ Use conventional commit messages
- ✅ Keep commits focused and atomic
- ✅ Write meaningful commit descriptions

---

## Documentation Constraints

### DO NOT

- ❌ Use marketing language or fluff
- ❌ Over-promise capabilities
- ❌ Include outdated/inaccurate information
- ❌ Add excessive comments or documentation

### DO

- ✅ Be professional and technical
- ✅ Focus on clarity and accuracy
- ✅ Document trade-offs and limitations
- ✅ Keep documentation maintainable

---

## Scope Constraints

### This Project WILL

<!-- Define what's in scope -->

- [In-scope item 1]
- [In-scope item 2]

### This Project WILL NOT

<!-- Define what's explicitly out of scope -->

- [Out-of-scope item 1]
- [Out-of-scope item 2]

---

## Task-Specific Constraints

<!-- Add constraints for specific tasks -->

### Documentation-Only Tasks

When a task is marked "documentation-only":

- ❌ Do NOT modify pipelines
- ❌ Do NOT change code behavior
- ❌ Do NOT alter policies or tests
- ✅ Only modify .md files as specified

### Pipeline Tasks

When modifying pipelines:

- ❌ Do NOT break existing functionality
- ❌ Do NOT remove security controls
- ✅ Maintain backward compatibility
- ✅ Test changes before pushing
