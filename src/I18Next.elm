module I18Next exposing
    ( Translations, Delims(..), Replacements, initialTranslations
    , translationsDecoder
    , t, tr, tf, trf
    , keys, hasKey
    , Tree, fromTree, string, object
    )

{-| This library provides a solution to load and display translations in your
app. It allows you to load json translation files, display the text and
interpolate placeholders. There is also support for fallback languages if
needed.


## Types and Data

@docs Translations, Delims, Replacements, initialTranslations


## Decoding

Turn your JSON into translations.

@docs translationsDecoder


## Using Translations

Get translated values by key straight away, with replacements, fallback languages
or both.

@docs t, tr, tf, trf


## Inspecting

You probably won't need these functions for regular applications if you just
want to translate some strings. But if you are looking to build a translations
editor you might want to query some information about the contents of the
translations.

@docs keys, hasKey


## Custom Building Translations

Most of the time you'll load your translations as JSON form a server, but there
may be times, when you want to build translations in your code. The following
functions let you build a `Translations` value programmatically.

@docs Tree, fromTree, string, object

-}

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)


{-| A type representing a hierarchy of nested translations. You'll only ever
deal with this type directly, if you're using
[`string`](I18Next#string) and [`object`](I18Next#object).
-}
type Tree
    = Branch (Dict String Tree)
    | Leaf String


{-| A type that represents your loaded translations
-}
type Translations
    = Translations (Dict String String)


{-| A union type for representing delimiters for placeholders. Most commonly
those will be `{{...}}`, or `__...__`. You can also provide a set of
custom delimiters(start and end) to account for different types of placeholders.
-}
type Delims
    = Curly
    | Underscore
    | Custom ( String, String )


{-| An alias for replacements for use with placeholders. Each tuple should
contain the name of the placeholder as the first value and the value for
the placeholder as the second entry. See [`tr`](I18Next#tr) and
[`trf`](I18Next#trf) for usage examples.
-}
type alias Replacements =
    List ( String, String )


{-| Use this to initialize Translations in your model. This may be needed
when loading translations but you need to initialize your model before
your translations are fetched.
-}
initialTranslations : Translations
initialTranslations =
    Translations Dict.empty


{-| Use this to obtain a list of keys that are contained in the translations.
From this it is simple to, for example, compare two translations for keys defined in one
but not the other. The order of the keys is arbitrary and should not be relied
on.
-}
keys : Translations -> List String
keys (Translations dict) =
    Dict.keys dict


{-| This function lets you check whether a certain key is exists in your
translations.
-}
hasKey : Translations -> String -> Bool
hasKey (Translations dict) key =
    Dict.member key dict


{-| Decode a JSON translations file. The JSON can be arbitrarly nested, but the
leaf values can only be strings. Use this decoder directly, if you are passing
the translations JSON into your elm app via flags or ports.
After decoding nested values will be available with any of the translate
functions separated with dots.

    {- The JSON could look like this:
    {
      "buttons": {
        "save": "Save",
        "cancel": "Cancel"
      },
      "greetings": {
        "hello": "Hello",
        "goodDay": "Good Day {{firstName}} {{lastName}}"
      }
    }
    -}

    --Use the decoder like this on a string
    import I18Next exposing (translationsDecoder)
    Json.Decode.decodeString translationsDecoder "{ \"greet\": \"Hello\" }"

    -- or on a Json.Encode.Value
    Json.Decode.decodeValue translationsDecoder encodedJson

-}
translationsDecoder : Decoder Translations
translationsDecoder =
    Decode.dict treeDecoder
        |> Decode.map (flattenTranslations >> Translations)


treeDecoder : Decoder Tree
treeDecoder =
    Decode.oneOf
        [ Decode.string |> Decode.map Leaf
        , Decode.lazy
            (\_ -> Decode.dict treeDecoder |> Decode.map Branch)
        ]


flattenTranslations : Dict String Tree -> Dict String String
flattenTranslations dict =
    flattenTranslationsHelp Dict.empty "" dict


flattenTranslationsHelp : Dict String String -> String -> Dict String Tree -> Dict String String
flattenTranslationsHelp initialValue namespace dict =
    Dict.foldl
        (\key val acc ->
            let
                newNamespace currentKey =
                    if String.isEmpty namespace then
                        currentKey

                    else
                        namespace ++ "." ++ currentKey
            in
            case val of
                Leaf str ->
                    Dict.insert (newNamespace key) str acc

                Branch children ->
                    flattenTranslationsHelp acc (newNamespace key) children
        )
        initialValue
        dict


{-| Translate a value at a given string.

    {- If your translations are { "greet": { "hello": "Hello" } }
    use dots to access nested keys.
    -}
    import I18Next exposing (t)
    t translations "greet.hello" -- "Hello"

-}
t : Translations -> String -> String
t (Translations translations) key =
    Dict.get key translations |> Maybe.withDefault key


replacePlaceholders : Replacements -> Delims -> String -> String
replacePlaceholders replacements delims str =
    let
        ( start, end ) =
            delimsToTuple delims
    in
    List.foldl
        (\( key, value ) acc ->
            String.replace (start ++ key ++ end) value acc
        )
        str
        replacements


delimsToTuple : Delims -> ( String, String )
delimsToTuple delims =
    case delims of
        Curly ->
            ( "{{", "}}" )

        Underscore ->
            ( "__", "__" )

        Custom tuple ->
            tuple


{-| Translate a value at a key, while replacing placeholders.
Check the [`Delims`](I18Next#Delims) type for
reference how to specify placeholder delimiters.
Use this when you need to replace placeholders.

    -- If your translations are { "greet": "Hello {{name}}" }
    import I18Next exposing (tr, Delims(..))
    tr translations Curly "greet" [("name", "Peter")]

-}
tr : Translations -> Delims -> String -> Replacements -> String
tr (Translations translations) delims key replacements =
    case Dict.get key translations of
        Just str ->
            replacePlaceholders replacements delims str

        Nothing ->
            key


{-| Translate a value and try different fallback languages by providing a list
of Translations. If the key you provide does not exist in the first of the list
of languages, the function will try each language in the list.

    {- Will use german if the key exists there, or fall back to english
    if not. If the key is not in any of the provided languages the function
    will return the key. -}
    import I18Next exposing (tf)
    tf [germanTranslations, englishTranslations] "labels.greetings.hello"

-}
tf : List Translations -> String -> String
tf translationsList key =
    case translationsList of
        (Translations translations) :: rest ->
            Dict.get key translations |> Maybe.withDefault (tf rest key)

        [] ->
            key


{-| Combines the [`tr`](I18Next#tr) and the [`tf`](I18Next#tf) function.
Only use this if you want to replace placeholders and apply fallback languages
at the same time.

    -- If your translations are { "greet": "Hello {{name}}" }
    import I18Next exposing (trf, Delims(..))
    let
      langList = [germanTranslations, englishTranslations]
    in
      trf langList Curly "greet" [("name", "Peter")] -- "Hello Peter"

-}
trf : List Translations -> Delims -> String -> Replacements -> String
trf translationsList delims key replacements =
    case translationsList of
        (Translations translations) :: rest ->
            case Dict.get key translations of
                Just str ->
                    replacePlaceholders replacements delims str

                Nothing ->
                    trf rest delims key replacements

        [] ->
            key


{-| Represents the leaf of a translations tree. It holds the actual translation
string.
-}
string : String -> Tree
string =
    Leaf


{-| Let's you arange your translations in a hierarchy of objects.
-}
object : List ( String, Tree ) -> Tree
object =
    Dict.fromList >> Branch


{-| Create a [`Translations`](I18Next#Translations) value from a list of pairs.

    import I18Next exposing (string, object, fromTree, t)

    translations =
        fromTree
          [ ("custom"
            , object
                [ ( "morning", string "Morning" )
                , ( "evening", string "Evening" )
                , ( "afternoon", string "Afternoon" )
                ]
            )
          , ("hello", string "hello")
          ]

    -- use it like this
    t translations "custom.morning" -- "Morning"

-}
fromTree : List ( String, Tree ) -> Translations
fromTree =
    Dict.fromList >> flattenTranslations >> Translations
