# Introduction

This is a small sample of code which I have produced for personal projects or
have been granted permission to use.

Few pieces of code contain validation as one can assume that the input has been
validated and verified before hand.

## Search.php
Wrapper around ElasticSearch.

## Geocoder.php
Basic CURL based Geocoding using Google API.

## cvbotd.coffee
This is my initial rough attempt at creating a CV converter.

## process_cv.py
Gearman worker for converting DOC, DOCX and PDFs to PNG and Plain text.

This can be improved easily with the new Python 3 subprocess module which
has a built-in timeout argument for the `call()` function.

This is a rewrite of cvbotd.coffee

## mail.py
IMAP Mailbox wrapper

## ssgen
Static Site Generator wrapper

## api.coffee
ZeroMQ based producer and interface to RethinkDB. This uses Q promises which
keep the callback structure pretty flat.

## status.rs
I use WMFS as my Window Manager. I thought I'd try Rust out for fun, this
definitely compiles with Rust 0.8 but as the interfaces keep changing I doubt it
will continue.

## main.py
A copy of a simple board game
