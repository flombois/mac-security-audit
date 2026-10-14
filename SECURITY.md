# Security policy

## Supported versions

Only the latest commit on `main` is supported. There are no releases yet.

## Reporting a vulnerability

Please don't open a public issue. Report it privately instead: on the repository's **Security** tab, click
**Report a vulnerability**. Include what you ran, on which macOS version, and what happened.

You should get an answer within a week. Once it's fixed, the advisory is published with credit, unless you
prefer to stay anonymous.

## Scope

The audit is meant to be read-only and never to print secret values. These count as vulnerabilities:

- a check that changes a setting, file or permission;
- a secret value printed to the terminal or written to the JSON report;
- text from the audited Mac (app or file names…) that can run or inject anything in the terminal;
- a command that runs as root beyond what `run_root_check` queues, or that prompts for a password.

A check that misses a weakness, or reports a false positive, is a normal bug: open an issue with the
**False negative** or **False positive** form.
