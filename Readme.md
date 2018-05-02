# Type of html

`type-of-html` is a library for generating html in a highly
performant, modular and type safe manner.

Please look at the documentation of the module for an overview of the api:
[Html](https://hackage.haskell.org/package/type-of-html/docs/Html.html)

Note that you need at least ghc 8.2.

## Typesafety

Part of the html spec is encoded at the typelevel, turning a lot of
mistakes into type errors.

Let's check out the /type safety/ in ghci:

```haskell
>>> td_ (tr_ "a")

<interactive>:1:1: error:
    • 'Tr is not a valid child of 'Td
    • In the expression: td_ (tr_ "a")
      In an equation for ‘it’: it = td_ (tr_ "a")

<interactive>:1:6: error:
    • 'Tr can't contain a string
    • In the first argument of ‘td_’, namely ‘(tr_ "a")’
      In the expression: td_ (tr_ "a")
      In an equation for ‘it’: it = td_ (tr_ "a")

>>> tr_ (td_ "a")
<tr><td>a</td></tr>
```

And

```haskell
>>> td_A (A.coords_ "a") "b"

<interactive>:1:1: error:
    • 'CoordsA is not a valid attribute of 'Td
    • In the expression: td_A (A.coords_ "a") "b"
      In an equation for ‘it’: it = td_A (A.coords_ "a") "b"

>>> td_A (A.id_ "a") "b"
<td id="a">b</td>
```

Every parent child relation of html elements is checked against the
specification of html and non conforming elements result in compile
errors.

The same is true for html attributes.

The checking is a bit lenient at the moment:

- some elements can't contain itself as any descendant: at the moment we look only at direct children. This allows some (quite exotic) invalid html documents.
- some elements change their permitted content based on attributes: we always allow content as if all relevant attributes are set.

Never the less: these cases are seldom.  In the vast majority of cases you're only allowed to construct valid html.
These restrictions aren't fundamental, they could be turned into compile time errors.  Perhaps a future version will be even more strict.

## Modularity

Html documents are just ordinary haskell values which can be composed or abstracted over:

```haskell
>>> let table = table_ . map (tr_ . map td_)
>>> :t table
table :: ('Td ?> a) => [[a]] -> 'Table > ['Tr > ['Td > a]]
>>> table [["A","B"],["C"]]
<table><tr><td>A</td><td>B</td></tr><tr><td>C</td></tr></table>
>>> import Data.Char
>>> html_ . body_ . table $ map (\c -> [[c], show $ ord c]) ['a'..'d']
<html><body><table><tr><td>a</td><td>97</td></tr><tr><td>b</td><td>98</td></tr><tr><td>c</td><td>99</td></tr><tr><td>d</td><td>100</td></tr></table></body></html>
```

And here's an example module:

```haskell
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds     #-}

module Main where

import Html

import qualified Html.Attribute as A

main :: IO ()
main
  = print
  . page
  $ map td_ [1..(10::Int)]

page
  :: 'Tr ?> a
  => a
  -> ('Div :@: ('ClassA := String # 'IdA := String))
        ( 'Div > String
        # 'Div > String
        # 'Table > 'Tr > a
        )
page tds =
  div_A (A.class_ "qux" # A.id_ "baz")
    ( div_ "foo"
    # div_ "bar"
    # table_ (tr_ tds)
    )
```

Please note that the type of `page` is inferable, so ask ghc-mod or
whatever you use to write it for you.  If you choose not to write the
types, you don't need the language extensions.  I strongly suggest
that you don't write type signatures for `type-of-html`.

All text will be automatically html escaped:

```haskell
>>> i_ "&"
<i>&amp;</i>

>>> div_A (A.id_ ">") ()
<div id="&gt;"></div>
```

If you want to opt out, wrap your types into the 'Raw'
constructor. This will increase performance, but can be only used with
trusted input. You can use this e.g. to embed some blaze-html code
into type-of-html.

```haskell
>>> i_ (Raw "</i><script></script><i>")
<i></i><script></script><i></i>
```

## Controlflow

You can use Either and Maybe in your documents:

```haskell
>>> div_ (Just (div_ "a"))
<div><div>a</div></div>

>>> div_ (if True then Nothing else Just (div_ "b"))
<div></div>

>>> div_ (if True then Left (div_ "a") else Right "b")
<div><div>a</div></div>

>>> div_A (if True then Right (A.id_ "a") else Left (A.class_ "a")) "b"
<div id="a">b</div>
```

If you use Either, both possible outcomes are typechecked if they are valid children.

You can combine Either, Maybe and Lists in any way you want.  The
types will get jolly complicated, but if you don't write the types,
you'll be good.

## Performance

`type-of-html` is a lot faster than `blaze-html` or than `lucid`.

Look at the following benchmarks:

Remember this benchmark from `blaze-html`?

![blaze](https://jaspervdj.be/blaze/images/benchmarks-bigtable.png)

This is comparing blaze with `type-of-html`:

![type-of-html](https://user-images.githubusercontent.com/5609565/37879227-765df128-3075-11e8-9270-3839ce1852c8.png)

To look at the exact code of this benchmark look into the repo.  The
big table benchmark here is only a 4x4 table. Using a 1000x10 table
like on the blaze homepage yields even better relative performance (~9
times faster), but would make the other benchmarks unreadable.

How is this possible? We supercompile lots of parts of the generation
process. This is possible thanks to the new features of GHC 8.2:
AppendSymbol. We represent tags and attributes as kinds and map these
to (a :: [Symbol]) and then fold all neighbouring Symbols with
AppendSymbol. Afterwards we reify the Symbols with symbolVal which
will be embedded in the executable as Addr#. All this happens at
compile time. At runtime we do only generate the content and append
Builders. Because all functions from this library get inlined, we'll
automatically profit from future optimizations in ByteString.Builder.

For example, if you write:

```haskell
renderText $ tr_ (td_ "test")
```

The compiler does optimize it to the following (well, unpackCString#
doesn't exist for Builder, so it's slightly more complicated):

```haskell
decodeUtf8 $ toLazyByteString
  (  Data.ByteString.Builder.unpackCString# "<tr><td>"#
  <> builderCString# "test"#
  <> Data.ByteString.Builder.unpackCString# "</tr>"#
  )
```

Note that the compiler automatically sees that your string literal
doesn't need utf8 and converts directly the `"test"# :: Addr#` to an
escaped Builder without any intermediate structure, not even an
allocated bytestring.

```haskell
renderByteString $ tr_ (td_ "teſt")
```

Results in

```haskell
toLazyByteString
  (  Data.ByteString.Builder.unpackCString# "<tr><td>"#
  <> encodeUtf8BuilderEscaped prim (Data.Text.unpackCString# "te\\197\\191t"#)
  <> Data.ByteString.Builder.unpackCString# "</tr>"#
  )
```

If you write

```haskell
renderBuilder $ div_ (div_ ())
```

The compiler does optimize it to the following:

```haskell
Data.ByteString.Builder.unpackCString# "<div><div></div></div>"#
```

This sort of compiletime optimization isn't for free, it'll increase
compilation times.

Note that compiling with `-O2` results in a ~25% faster binary than
with `-O` and compiling with `-O0` compiles about 15 times faster, so
be sure that you develop with `-O0` and benchmark or deploy with
`-O2`.  Be aware, that cabal compiles only with `-O` if you don't
specify explicitly otherwise.

### Even faster

Need for speed?  Consider following advise, which is sorted in
ascending order of perf gains:

If you've got attributes or contents of length 1, use a Char.

This allows for a more efficient conversion to builder, because we
know the length at compile time.

```haskell
div_ 'a'
```

If you know for sure that you don't need escaping, use `Raw`.

This allows for a more efficient conversion to builder, because we
don't need to escape.

```haskell
div_ (Raw "abc")
```

If you've got numeric attributes or contents, don't convert it to a
string.

This allows for a more efficient conversion to builder, because we
don't need to escape and don't need to handle utf8.

```haskell
div_ (42 :: Int)
```

If you know that an attribute or content is empty, use `()`.

This allows for more compile time appending and avoids two runtime
appends.

```haskell
div_ ()
```

If you know for sure a string at compile time which doesn't need
escaping, use a `Proxy Symbol`.

This allows for more compile time appending and avoids two runtime
appends, escaping and conversion to a builder.

```haskell
div_ (Proxy @"hello")
```

These techniques can have dramatic performance implications,
especially the last two. If you replace for example in the `big page
with attributes` benchmark every string with a Proxy Symbol, it'll run
in 10 ns which is 500 times faster than `blaze-html`.  Looking at core
shows that this is equivalent of directly embedding the entire
resulting html as bytestring in the binary and is therefore the
fastest possible output.

Please consider as well using the packages
[https://hackage.haskell.org/package/type-of-html-static](type-of-html-static)
which provides helper TH functions to optimize even more at compile
time.  It was put in a seperate package to avoid a dependency on TH
(which would've been handy for the functions in `Html.Element`).  You
can achieve more or less 5x faster rendering when applying these
optimizations.  The actual performance gain depends a lot on the
structure of your document.

## Comparision to lucid and blaze-html

Advantages of `type-of-html`:
- more or less 10 times faster on a medium sized page
- a lot higher type safety: nearly no invalid document is inhabited
- fewer dependencies

Disadvantages of 'type-of-html':
- a bit noisy syntax (don't write types!)
- sometimes unusual type error messages
- compile times (30sec for a medium sized page, with `-O0` only ~2sec)
- needs at least ghc 8

I'd generally recommend that you put your documents into an extra
module to avoid frequent recompilations.  Additionally you can use
`type-of-html` within an `blaze-html` document and vice versa.  This
allows you to gradually migrate, or only write the hotpath in a more
efficient representation.

## Example usage

```haskell
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module Main where

import Html

import Data.Text.Lazy.IO as TL

main :: IO ()
main = TL.putStrLn $ renderText example

example =
  html_
    ( body_
      ( h1_
        ( img_
        # strong_ "foo"
        )
      # div_
        ( div_ "bar"
        )
      # div_
        ( form_
          ( fieldset_
            ( div_
              ( div_
                ( label_ "zot"
                # select_
                  ( option_ 'b'
                  # option_ 'c'
                  )
                # map div_ [1..5 :: Int]
                )
              )
            # button_ (i_ ())
            )
          )
        )
      )
    )
```

## FAQ

### Why don't you provide a pretty printer?

It's sadly not possible to pretty print html source in a semantic preserving way.
If you add before every tag a newline and indentation, the following happens:

```html
<i>a</i><em>b</em>
```

```html
<i>
  a
</i>
<em>
  b
</em>
```

This would add a space when rendering.  So perhaps we'll avoid all
these text modifying tags, but now look at `<pre>`. Every whitespace
and newline within is semantically important.  And even if we avoid
modifying stuff within `<pre>`, there is the nasty css property
`white-space: pre;`. With this, all bets are off to modify any
indenting, because we can't know which css will apply to the document:
- It may include a link, so it would be dynamic.
- There might be meddling javascript.
- The user of the browser is free to activate a custom css.

If we go creative, there is still one option:

```html
<div
  ><div
    >Hello World!</div
  ></div
>
```

This would be semantically correct, but would this be pretty?

I recommend, that if you want to debug html, use mozilla fire bug, so
you can as well fold trees and look at the rendering.

### Why don't you keep track of appended tag lengths at compile time?
Well, it's true that we could improve performance a miniscule by that:
by knowing the length of the string, we could just use internal
bytestring functions to copy over the addr#.  This would avoid a ccall
to determine the length of the addr# more or less per tag.

At the other hand, luckily ghc moves all these bytestrings to the
toplevel in core, so we have this cost only the first time we use this
bytestring.  Considering that most webpages have a lot more than one
visitor, this dwarfs the cost (about 3 nanoseconds) a lot.

The negative side of doing this would be a severe complication for the
typechecker, which is already quite stressed with this library.

Besides, there is a ghc ticket about replacing compile time strings
(addr#) with bytearray#, which contains it's length. So in some
future, we'll have this for free.

### Wouldn't it be more efficient to append all compile time stuff to one huge Symbol and use '[(Nat,Nat)] to slice it?
Cool idea, but no.  This would reduce memory fragmentation and avoid a
terminating null more or less per tag at the cost of the lost of
sharing. Being unable to inspect a Symbol, we would end up with a lot
of repetitions, which are at the moment shared.  Even the bytestring,
which is used for the Symbol, is shared of equal Symbols.

### Isn't there any performance tweak left?
At the moment, string literals are handled well, but not optimal.  The
escaping of string literals is done everytime when rendering the html
document, ideally we convince GHC to float the escaped string literal
to top level.  I guess, that would make things a bit faster.
