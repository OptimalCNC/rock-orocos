# Planned Work / TODO

These chapters describe approved work that is not implemented and is not part
of the current install contract.

> [!IMPORTANT]
> Do not use these pages as documentation for current runtime behavior. Follow
> the User Guide and Reference for supported behavior.

| Planned capability | Current gap |
|---|---|
| [Workspace Source Update Command](./source-update-command-design.md) | Updating the root and Autoproj-managed package sources requires separate commands. |
| [OPC UA PKI And Authorization](./opcua-security-prd.md) | The native endpoint remains loopback-only. |
| [Deployer TUI](./deployer-tui-prd.md) | The supported operator interface remains the classic deployer and TaskBrowser. |

When one of these capabilities ships, migrate its durable behavior into the
relevant guide or reference chapter and delete its TODO page.
