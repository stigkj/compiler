{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wall #-}

module Canonicalize.Environment.Dups
  ( detect,
    checkFields,
    checkFields',
    Dict,
    none,
    one,
    insert,
    union,
    unions,
  )
where

import Data.Map qualified as Map
import Data.Name qualified as Name
import Data.OneOrMore qualified as OneOrMore
import Reporting.Annotation qualified as A
import Reporting.Error.Canonicalize qualified as Error
import Reporting.Result qualified as Result

-- DUPLICATE TRACKER

type Dict value =
  Map.Map Name.Name (OneOrMore.OneOrMore (Info value))

data Info value = Info
  { _region :: A.Region,
    _value :: value
  }

-- DETECT

type ToError =
  Name.Name -> A.Region -> A.Region -> Error.Error

detect :: ToError -> Dict a -> Result.Result i w Error.Error (Map.Map Name.Name a)
detect toError dict =
  Map.traverseWithKey (detectHelp toError) dict

detectHelp :: ToError -> Name.Name -> OneOrMore.OneOrMore (Info a) -> Result.Result i w Error.Error a
detectHelp toError name values =
  case values of
    OneOrMore.One (Info _ value) ->
      return value
    OneOrMore.More left right ->
      let (Info r1 _, Info r2 _) =
            OneOrMore.getFirstTwo left right
       in Result.throw (toError name r1 r2)

-- CHECK FIELDS

checkFields :: [(A.Located Name.Name, a, comments)] -> Result.Result i w Error.Error (Map.Map Name.Name a)
checkFields fields =
  detect Error.DuplicateField (foldr addField none fields)

addField :: (A.Located Name.Name, a, comments) -> Dict a -> Dict a
addField (A.At region name, value, _) dups =
  Map.insertWith OneOrMore.more name (OneOrMore.one (Info region value)) dups

checkFields' :: (A.Region -> a -> b) -> [(A.Located Name.Name, a, comments)] -> Result.Result i w Error.Error (Map.Map Name.Name b)
checkFields' toValue fields =
  detect Error.DuplicateField (foldr (addField' toValue) none fields)

addField' :: (A.Region -> a -> b) -> (A.Located Name.Name, a, comments) -> Dict b -> Dict b
addField' toValue (A.At region name, value, _) dups =
  Map.insertWith OneOrMore.more name (OneOrMore.one (Info region (toValue region value))) dups

-- BUILDING DICTIONARIES

none :: Dict a
none =
  Map.empty

one :: Name.Name -> A.Region -> value -> Dict value
one name region value =
  Map.singleton name (OneOrMore.one (Info region value))

insert :: Name.Name -> A.Region -> a -> Dict a -> Dict a
insert name region value dict =
  Map.insertWith (\new old -> OneOrMore.more old new) name (OneOrMore.one (Info region value)) dict

union :: Dict a -> Dict a -> Dict a
union a b =
  Map.unionWith OneOrMore.more a b

unions :: [Dict a] -> Dict a
unions dicts =
  Map.unionsWith OneOrMore.more dicts
