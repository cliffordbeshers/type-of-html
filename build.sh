#!/bin/bash

cabal new-build --project client.project all
cabal new-build --project server.project all
