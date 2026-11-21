# Contributing

Bug reports and small, focused pull requests are welcome.

Before a pull request can be merged you'll be asked to agree that madebyjinn may ship your contribution in
the signed build of Gus that is sold at madebyjinn.com/gus, and relicense it if the project's licence ever
changes. Your contribution stays available here under the GPL either way.

To build and test:

```
scripts/build.sh        # needs Xcode 26 and XcodeGen; set your own team in project.yml
scripts/test.sh         # unit tests
scripts/selftest.sh     # every feature, inside the app (see Tests/TEST-CASES.md)
```

Keep it small and fast: Gus is one field, and anything new should stay out of the way until it's typed for.
