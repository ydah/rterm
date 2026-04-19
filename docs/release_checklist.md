# Release Checklist

- Run `bundle exec rspec`.
- Run `bundle exec rake package:verify_contents`.
- Run `npm pack --dry-run` only if JavaScript packaging is introduced.
- Update `lib/rterm/version.rb`.
- Update changelog or release notes.
- Confirm examples run against the released API.
- Confirm no `.idea`, `.github`, `spec`, `tmp`, `pkg`, generated docs, or local lock files are included in the gem.
- Tag the release after the gem artifact has been checked.
