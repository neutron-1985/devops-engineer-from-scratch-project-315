# common/host_prerequisites

Installs operating-system packages required by every managed infrastructure host.
Service-specific dependencies remain in the roles that own those services.

## Variables

`host_prerequisites_packages` is the list of common packages to install. It
contains `logrotate` by default.

## Example

```yaml
roles:
  - role: common/host_prerequisites
```
