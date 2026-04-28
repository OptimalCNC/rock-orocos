# autoproj

This directory is reserved for the tracked autoproj control files of the
workspace.

Expected first contents:

- `manifest`
- `init.rb`
- `overrides.yml`
- `overrides.rb`

These files should define:

- package selection
- package-set bootstrap hooks
- source overrides
- package pins
- OCL enablement
- RTT scripting enablement

Generated workspace state does not belong here.
