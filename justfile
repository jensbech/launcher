set shell := ["bash", "-cu"]

default:
    @just --list

build:
    ./scripts/build-app.sh

icon:
    ./scripts/make-icon.sh

test *ARGS:
    ./scripts/test.sh {{ARGS}}

run: build
    open build/Sift.app

install:
    ./scripts/install-app.sh

sudoers:
    ./scripts/setup-sudoers.sh

dev:
    swift run Sift

clean:
    rm -rf .build build
