---
title: Cheatsheet
description: The call for the thing you need, with what it actually returns.
---

Everything below is real output. Start here, then use the
[generator reference](/api/) when you need the whole list.

```swift
import Decoy
import DecoyLocaleEN

// Seeded — the same values every run.
var faker = Faker(seed: 1337, locale: DecoyLocaleEN.locale)

// Or don't pass one, and get something different each time.
var faker = Faker(locale: DecoyLocaleEN.locale)
```

A seed is any number you pick; the same one always produces the same values. Leave it out
and one is chosen for you — readable afterwards as `faker.seed`. See
[quick start](/start/quick-start/).

## People

| I need | Call | Returns |
|---|---|---|
| A full name | `faker.person.fullName()` | `Abigail Crum Jr.` |
| First / last separately | `faker.person.firstName()` · `.lastName()` | `Mary` · `Szymanski` |
| A name of a given gender | `faker.person.firstName(.female)` | `Janet` |
| An honorific | `faker.person.prefix()` | `Prof.` |
| A surname nobody really has | `faker.person.novelLastName()` | `Mountagnolds` |
| A job title | `faker.person.jobTitle()` | `Managed concept Executive` |
| A social security number | `faker.person.ssn()` | `570-08-7268` |
| A blood type | `faker.person.bloodType()` | `A+` |

## Contact details

| I need | Call | Returns |
|---|---|---|
| An email | `faker.internet.email()` | `charles.garcia@example.org` |
| A username | `faker.internet.username()` | `charles7332` |
| A phone number | `faker.phone.number()` | `(523) 896-6598` |
| A URL | `faker.internet.url()` | `https://bruggeman.shangrila` |
| An IP address | `faker.internet.ipv4()` · `.ipv6()` | `69.62.101.92` |
| A password | `faker.internet.password()` | |
| A user agent | `faker.internet.userAgent()` | |

Emails use reserved example domains, so nothing you generate can reach a real inbox.

## Addresses

| I need | Call | Returns |
|---|---|---|
| A street address | `faker.location.streetAddress()` | `14313 Edge Freeway` |
| A full postal address | `faker.location.postalAddress()` | multi-line, in local layout |
| A city | `faker.location.city()` | `Duchesne` |
| A country | `faker.location.country()` | |
| **A city, region and postcode that agree** | `faker.location.placeAndPostcode()` | `(city: "Parsonsfield", state: "Maine", stateCode: "ME", postcode: "04321")` |
| Coordinates | `faker.location.coordinate()` | |
| Coordinates near a point | `faker.location.coordinate(near: (51.5, -0.12), radiusKm: 5)` | |

Draw the tuple rather than three separate calls if the fields end up in the same row.
Independent draws give you Boston, California, 10001.

## Business

| I need | Call | Returns |
|---|---|---|
| A company name | `faker.company.name()` | `Martinez-Cornett` |
| A legal form | `faker.company.legalEntityType()` | per jurisdiction |
| A product name | `faker.commerce.productName()` | `Awesome Cotton Computer` |
| A price | `faker.commerce.price()` | |
| A product review | `faker.commerce.review()` | weighted J-shaped, like real ratings |
| A department | `faker.commerce.department()` | |
| A barcode | `faker.commerce.ean()` | valid check digit |

## Money

| I need | Call | Returns |
|---|---|---|
| An IBAN | `faker.finance.iban()` | `GB58WIGE97359659180210` |
| A card number | `faker.finance.creditCardNumber()` | `4116189192839904` — passes Luhn |
| An account number | `faker.finance.accountNumber()` | |
| A currency | `faker.finance.currency()` | code, name and symbol together |
| A transaction description | `faker.finance.transactionDescription()` | |

Card numbers and IBANs carry correct check digits, so they survive validation without
being usable for anything.

## Identifiers

| I need | Call | Returns |
|---|---|---|
| A UUID | `faker.uuid()` | `5d1743f8-be0b-43b9-be2d-34fe10ab1b00` |
| A sortable UUID | `faker.uuidV7()` | time-ordered |
| A hash | `faker.crypto.sha256()` | `cbc21f0b606da459…` |
| A wallet address | `faker.crypto.ethereumAddress()` | checksummed |
| A number matching a mask | `faker.numerify("+1 (###) ###-####")` | `+1 (339) 237-5868` |
| Letters and digits | `faker.bothify("??-####-%#")` | `HP-6857-58` |

## Dates

| I need | Call | Returns |
|---|---|---|
| A past date | `faker.instant.past(years: 3)` | `2025-07-16T23:18:40Z` |
| A future date | `faker.instant.future()` | `2026-10-03T16:22:19Z` |
| A birthdate | `faker.instant.birthdate()` | |
| Between two instants | `faker.instant.between(start, end)` | |
| As a `Foundation.Date` | `faker.date.past()` | same value, different type |

Dates are relative to a fixed reference instant, not to `now` — otherwise seed 1337
would give different fixtures tomorrow than today. Pass your own with
`Faker(seed:reference:)`.

## Text

| I need | Call | Returns |
|---|---|---|
| A sentence | `faker.lorem.sentence()` | `Morio lapis betis gurculio…` |
| Paragraphs | `faker.lorem.paragraphs(3)` | |
| A single word | `faker.word.noun()` · `.verb()` · `.adjective()` | `mazurka` |
| A slug | `faker.lorem.slug()` | |

## Files and systems

| I need | Call | Returns |
|---|---|---|
| A file name | `faker.system.fileName()` | `gens-conservatio.exp` |
| A MIME type | `faker.system.mimeType()` | `image/vnd.fpx` |
| A semantic version | `faker.system.semver()` | |
| **A database error** | `faker.system.databaseError()` | `too many connections for role "reporting"` |
| An HTTP failure | `faker.system.httpError()` | |
| A validation message | `faker.system.validationError()` | |

Error messages exist because every application has an error column, and seeding it with
lorem tells you nothing about how the column behaves when something 120 characters long
carrying a quoted identifier lands in it.

## Everything else

| I need | Call | Returns |
|---|---|---|
| A colour | `faker.color.hex()` · `.human()` | `#caa91f` |
| A vehicle plate | `faker.vehicle.registrationPlate()` | `HB-168-QD` |
| An airport | `faker.airline.airport()` | IATA code and name together |
| A chemical element | `faker.science.chemicalElement()` | |
| An SI unit | `faker.science.unit()` | `["name": "Beaufort", "symbol": "B"]` |
| A database engine | `faker.database.engine()` | `InnoDB` |
| An animal, cheese, mountain, composer | `faker.animal.animal()` and friends | see [real-world lists](/api/animal/) |
| A pub, a beer, a superhero | `faker.whimsy.pubName()` and friends | see [invented](/api/whimsy/) |

## Generating many at once

```swift
let users = Forge<User>("User") { User() }
    .rule(\.name) { $0.person.fullName() }
    .rule(\.email) { "user\($0.index)@example.com" }
    .locale(DecoyLocaleEN.locale)

users.generate(1_000, seed: 1337)
```

See [Forges](/guides/forges/) for traits, uniqueness and relationships.
