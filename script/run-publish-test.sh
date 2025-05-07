#!/bin/bash

dart format . && dart analyze && dart doc && dart test && dart pub publish --dry-run
