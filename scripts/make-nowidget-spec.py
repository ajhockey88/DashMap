#!/usr/bin/env python3
"""Writes project-nowidget.yml: project.yml without the Dynamic Island widget extension.

A free Apple ID can only register 10 App IDs a week and the widget needs its own, so a build
without it is easier to sideload."""
import re
import sys

src = open("project.yml").read()
src = src.replace("      - target: DashMapWidgets\n", "")
# The widget target is the last block in the spec.
src = re.sub(r"\n  DashMapWidgets:\n(?:    .*\n|\n)*", "\n", src)
if "DashMapWidgets" in src:
    sys.exit("failed to strip the widget target")
open("project-nowidget.yml", "w").write(src)
print("wrote project-nowidget.yml")
