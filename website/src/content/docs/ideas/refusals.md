---
title: What we refused
description: The sources that were offered, looked plausible, and were declined anyway.
---

This is the most interesting part of the project and the least visible, so it is written
down. Every one of these was a real offer that would have made the corpus bigger.

## Rosters of real people

Election candidate registers, company director filings and academic author lists are
open, machine-readable, frequently CC BY, and full of names. They are also lists of
identifiable individuals — usually with a constituency, an affiliation or an employer
attached.

The distinction that matters: **a register counts how many people hold a name; a roster
names them.** The first is a statistical fact about a language. The second is a file
about particular human beings, and `lastName()` sits beside a generator whose entire
purpose is returning surnames nobody is recorded as having.

One national election database was offered on exactly these grounds and declined.

## Corpora that arrive with a licence file

A repository's LICENSE states what its owner grants. It says nothing about where the
data came from.

Of the scraped name corpora surveyed:

- one Apache-2.0 set is built from the 533-million-account Facebook breach
- one language's name list self-describes as extracted from leaked election data
- one CC0 dataset is Wikipedia-derived, which is CC BY-SA laundering

Three known-bad in one small survey is the base rate, not bad luck. A permissive licence
on a scraped corpus is a claim about the scraper's intentions, not about the provenance
of what was scraped.

## Share-alike, however it arrives

Decoy is Apache-2.0 and must stay distributable as such. That rules out CC BY-SA, ODbL
and GPL data no matter how good it is — including the several excellent Wikipedia-derived
name and place datasets that would otherwise close real gaps.

The licence checker enforces this mechanically against a compatibility allow-list rather
than trusting a descriptor's word for it.

## Twelve locales

Removed rather than shipped nameless: Afrikaans, Dhivehi, Esperanto, Kurdish in both
scripts, Mongolian, Nepali, Tamil, Thai, Urdu, Uzbek and Zulu.

Each was a *language root* — no same-language ancestor to inherit from — carrying no
personal names of its own, so every person it generated was English wearing its postcode.

The criterion is deliberately not volume. Tamil shipped 15,612 native values and Thai
10,581. Removing them cost real data — month names, cities, postcodes, phone formats —
and keeping them cost the credibility of every record they produced.

It is also not thinness. `en_US` supplies no names either and is perfectly fine, because
it inherits from `en`, which is its own language. Regional variants are supposed to be
thin.

## What was allowed, after being refused for months

Animals, produce, cheeses, mountains, books, composers, universities, football clubs.

These failed the same test the invented namespaces pass — there *is* a fact of the matter
about whether an otter is an animal — so they wanted a citable source, and no suitable
one exists. Wikidata's taxonomy is not a colloquial animal list; Wikipedia's categories
are share-alike; the open food databases are product catalogues.

The reasoning was sound and the conclusion was wrong. It treated *cannot be mechanically
verified* as *cannot be shipped*, and a fixture library that will not tell you an otter
is an animal is not being rigorous.

What the discipline actually buys is knowing **which** data is checked. So these live
under their own source whose descriptor states plainly that accuracy is high and
**unverified**: written from general knowledge, with no upstream to hash and nothing for
the pipeline to re-check. An error there is an error, not a licence problem, and it is
fixable in a diff.

## What is still refused

Trademarked fictional universes. Curated joke corpora, which are somebody's authorship
rather than fact. And anything that would name a private individual.
