{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TypeFamilies #-}

module Main (main) where

import Chronos.Types
import Data.ByteString (ByteString)
import Data.Int (Int64)
import Data.List (intercalate)
import Data.Text (Text)
import Data.Text.Lazy.Builder (Builder)
import Test.Framework (defaultMain,defaultMainWithOpts,testGroup,Test)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit (Assertion,(@?=),assertBool)
import Test.QuickCheck (Gen, Arbitrary(..),discard,choose,arbitraryBoundedEnum,genericShrink,elements, suchThat)
import Test.QuickCheck.Property (failed,succeeded,Result(..))
import qualified Chronos as C
import qualified Data.Attoparsec.ByteString as AttoBS
import qualified Data.Attoparsec.Text as Atto
import qualified Data.ByteString.Builder as BBuilder
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LText
import qualified Data.Text.Lazy.Builder as Builder
import qualified Test.Framework as TF
import qualified Test.Framework.Providers.HUnit as PH
import qualified Torsor as T

-- We increase the default number of property-based tests (provided
-- by quickcheck) to 1000. Some of the encoding and decoding functions
-- we test have special behavior when the minute is zero, which only
-- happens in 1/60 of the generated scenarios. If we only generate 100
-- scenarios, there is a 18.62% chance that none of these will have zero
-- as the minute. If we increase this to 1000, that probability drops to
-- almost nothing.
main :: IO ()
main = defaultMainWithOpts tests mempty
  { TF.ropt_test_options = Just mempty
    { TF.topt_maximum_generated_tests = Just 1000
    , TF.topt_maximum_unsuitable_generated_tests = Just 10000
    }
  }

tests :: [Test]
tests =
  [ testGroup "Time of Day"
    [ testGroup "Text"
      [ testGroup "Text Parsing Spec Tests"
        [ PH.testCase "No Separator + microseconds"
            (timeOfDayParse Nothing "165956.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + microseconds"
            (timeOfDayParse (Just ':') "16:59:56.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + milliseconds"
            (timeOfDayParse (Just ':') "05:00:58.675" (TimeOfDay 05 00 58675000000))
        , PH.testCase "Separator + deciseconds"
            (timeOfDayParse (Just ':') "05:00:58.9" (TimeOfDay 05 00 58900000000))
        , PH.testCase "Separator + no subseconds"
            (timeOfDayParse (Just ':') "23:08:01" (TimeOfDay 23 8 1000000000))
        , PH.testCase "Separator + nanoseconds"
            (timeOfDayParse (Just ':') "05:00:58.111222999" (TimeOfDay 05 00 58111222999))
        , PH.testCase "Separator + 10e-18 seconds (truncate)"
            (timeOfDayParse (Just ':') "05:00:58.111222333444555666" (TimeOfDay 05 00 58111222333))
        , PH.testCase "Separator + opt seconds (absent)"
            (parseMatch (C.parser_HMS_opt_S (Just ':')) "00:01" (TimeOfDay 0 1 0))
        , PH.testCase "Separator + opt seconds (present)"
            (parseMatch (C.parser_HMS_opt_S (Just ':')) "00:01:05" (TimeOfDay 0 1 5000000000))
        , PH.testCase "No Separator + opt seconds (absent)"
            (parseMatch (C.parser_HMS_opt_S Nothing) "0001" (TimeOfDay 0 1 0))
        , PH.testCase "No Separator + opt seconds (present)"
            (parseMatch (C.parser_HMS_opt_S Nothing) "000105" (TimeOfDay 0 1 5000000000))
        ]
      , testGroup "Text Builder Spec Tests"
        [ PH.testCase "No Separator + microseconds"
            (timeOfDayBuilder (SubsecondPrecisionFixed 6) Nothing "165956.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + microseconds"
            (timeOfDayBuilder (SubsecondPrecisionFixed 6) (Just ':') "16:59:56.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + no subseconds"
            (timeOfDayBuilder (SubsecondPrecisionFixed 0) (Just ':') "23:08:01" (TimeOfDay 23 8 1000000000))
        ]
      , testProperty "Text Builder Parser Isomorphism (H:M:S)" $ propEncodeDecodeIso
          (LText.toStrict . Builder.toLazyText . C.builder_HMS (SubsecondPrecisionFixed 9) (Just ':'))
          (either (const Nothing) Just . Atto.parseOnly (C.parser_HMS (Just ':')))
      ]
    , testGroup "ByteString"
      [ testGroup "Parser Spec Tests"
        [ PH.testCase "No Separator + microseconds"
            (bsTimeOfDayParse Nothing "165956.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + microseconds"
            (bsTimeOfDayParse (Just ':') "16:59:56.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + milliseconds"
            (bsTimeOfDayParse (Just ':') "05:00:58.675" (TimeOfDay 05 00 58675000000))
        , PH.testCase "Separator + deciseconds"
            (bsTimeOfDayParse (Just ':') "05:00:58.9" (TimeOfDay 05 00 58900000000))
        , PH.testCase "Separator + no subseconds"
            (bsTimeOfDayParse (Just ':') "23:08:01" (TimeOfDay 23 8 1000000000))
        , PH.testCase "Separator + nanoseconds"
            (bsTimeOfDayParse (Just ':') "05:00:58.111222999" (TimeOfDay 05 00 58111222999))
        , PH.testCase "Separator + 10e-18 seconds (truncate)"
            (bsTimeOfDayParse (Just ':') "05:00:58.111222333444555666" (TimeOfDay 05 00 58111222333))
        , PH.testCase "Separator + opt seconds (absent)"
            (bsParseMatch (C.parserUtf8_HMS_opt_S (Just ':')) "00:01" (TimeOfDay 0 1 0))
        , PH.testCase "Separator + opt seconds (present)"
            (bsParseMatch (C.parserUtf8_HMS_opt_S (Just ':')) "00:01:05" (TimeOfDay 0 1 5000000000))
        , PH.testCase "No Separator + opt seconds (absent)"
            (bsParseMatch (C.parserUtf8_HMS_opt_S Nothing) "0001" (TimeOfDay 0 1 0))
        , PH.testCase "No Separator + opt seconds (present)"
            (bsParseMatch (C.parserUtf8_HMS_opt_S Nothing) "000105" (TimeOfDay 0 1 5000000000))
        ]
      , testGroup "Builder Spec Tests"
        [ PH.testCase "No Separator + microseconds"
            (bsTimeOfDayBuilder (SubsecondPrecisionFixed 6) Nothing "165956.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + microseconds"
            (bsTimeOfDayBuilder (SubsecondPrecisionFixed 6) (Just ':') "16:59:56.246052" (TimeOfDay 16 59 56246052000))
        , PH.testCase "Separator + no subseconds"
            (bsTimeOfDayBuilder (SubsecondPrecisionFixed 0) (Just ':') "23:08:01" (TimeOfDay 23 8 1000000000))
        ]
      , testProperty "Builder Parser Isomorphism (H:M:S)" $ propEncodeDecodeIso
          (LByteString.toStrict . BBuilder.toLazyByteString . C.builderUtf8_HMS (SubsecondPrecisionFixed 9) (Just ':'))
          (either (const Nothing) Just . AttoBS.parseOnly (C.parserUtf8_HMS (Just ':')))
      ]
    ]
  , testGroup "Date"
    [ testGroup "Parser Spec Tests" $
      [ PH.testCase "No Separator"
          (dateParse Nothing "20160101" (Date (Year 2016) (Month 0) (DayOfMonth 1)))
      , PH.testCase "Separator 1"
          (dateParse (Just '-') "2016-01-01" (Date (Year 2016) (Month 0) (DayOfMonth 1)))
      , PH.testCase "Separator 2"
          (dateParse (Just '-') "1876-09-27" (Date (Year 1876) (Month 8) (DayOfMonth 27)))
      ]
    , testGroup "Builder Spec Tests" $
      [ PH.testCase "No Separator"
          (dateBuilder Nothing "20160101" (Date (Year 2016) (Month 0) (DayOfMonth 1)))
      , PH.testCase "Separator 1"
          (dateBuilder (Just '-') "2016-01-01" (Date (Year 2016) (Month 0) (DayOfMonth 1)))
      , PH.testCase "Separator 2"
          (dateBuilder (Just '-') "1876-09-27" (Date (Year 1876) (Month 8) (DayOfMonth 27)))
      ]
    , testProperty "Builder Parser Isomorphism (Y-m-d)" $ propEncodeDecodeIso
        (LText.toStrict . Builder.toLazyText . C.builder_Ymd (Just '-'))
        (either (const Nothing) Just . Atto.parseOnly (C.parser_Ymd (Just '-')))
    ]
  , testGroup "Datetime"
    [ testProperty "Builder Parser Isomorphism (Y-m-dTH:M:S)" $ propEncodeDecodeIsoSettings
        (\format -> LText.toStrict . Builder.toLazyText . C.builder_YmdHMS (SubsecondPrecisionFixed 9) format)
        (\format -> either (const Nothing) Just . Atto.parseOnly (C.parser_YmdHMS format))
    , testProperty "Builder Parser Isomorphism (YmdHMS)" $ propEncodeDecodeIso
        (LText.toStrict . Builder.toLazyText . C.builder_YmdHMS (SubsecondPrecisionFixed 9) (DatetimeFormat Nothing Nothing Nothing))
        (either (const Nothing) Just . Atto.parseOnly (C.parser_YmdHMS (DatetimeFormat Nothing Nothing Nothing)))
    ]
  , testGroup "Offset Datetime"
    [ testGroup "Builder Spec Tests" $
      [ PH.testCase "W3C" $ matchBuilder "1997-07-16T19:20:30.450+01:00" $
          C.builderW3Cz $ OffsetDatetime
            ( Datetime
              ( Date (Year 1997) C.july (DayOfMonth 16) )
              ( TimeOfDay 19 20 30450000000 )
            ) (Offset 60)
      ]
    , testProperty "Builder Parser Isomorphism (YmdHMSz)" $ propEncodeDecodeIsoSettings
        (\(offsetFormat,datetimeFormat) offsetDatetime ->
            LText.toStrict $ Builder.toLazyText $
              C.builder_YmdHMSz offsetFormat (SubsecondPrecisionFixed 9) datetimeFormat offsetDatetime
        )
        (\(offsetFormat,datetimeFormat) input ->
            either (const Nothing) Just $ flip Atto.parseOnly input $
              C.parser_YmdHMSz offsetFormat datetimeFormat
        )
    ]
  , testGroup "Posix Time"
    [ PH.testCase "Get now" $ do
        now <- C.now
        assertBool "Current time is the beginning of the epoch." (now /= C.epoch)
    ]
  , testGroup "Conversion"
    [ testGroup "POSIX to Datetime"
      [ PH.testCase "Epoch" $ C.timeToDatetime (Time 0)
          @?= Datetime (Date (Year 1970) C.january (DayOfMonth 1))
                       (TimeOfDay 0 0 0)
      , PH.testCase "Billion Seconds" $ C.timeToDatetime (Time $ 10 ^ 18)
          @?= Datetime (Date (Year 2001) C.september (DayOfMonth 9))
                       (TimeOfDay 1 46 (40 * 10 ^ 9))
      , testProperty "Isomorphism" $ propEncodeDecodeFullIso C.timeToDatetime C.datetimeToTime
      ]
    ]
  , testGroup "TimeInterval"
    [ testGroup "within"
      [ testProperty "Verify that Time bounds are inside TimeInterval" propWithinInsideInterval
      , testProperty "Verify that the sum of Time and the span of TimeInterval is outside the interval"
          propWithinOutsideInterval
      ]
    , testGroup "timeIntervalToTimespan"
      [ PH.testCase "Verify Timespan correctness with TimeInterval"
          (C.timeIntervalToTimespan (TimeInterval (Time 13) (Time 25)) @?= Timespan 12)
      , PH.testCase "Verify Timespan correctness with equal TimeInterval bounds"
          (C.timeIntervalToTimespan (TimeInterval (Time 13) (Time 13)) @?= Timespan 0)
      , testProperty "Almost isomorphism" propEncodeDecodeTimeInterval
      ]
    , testGroup "whole"
      [ PH.testCase "Verify TimeInterval's bound correctness"
          (C.whole @?= TimeInterval (Time (minBound :: Int64)) (Time (maxBound :: Int64)))
      ]
    , testGroup "singleton"
      [ testProperty "Verify that upper and lower bound are always equals" propSingletonBoundsEquals
      ]
    , testGroup "width"
      [ testProperty "Verify Time bounds correctness with TimeSpan" propWidthVerifyBounds
      ]
    , testGroup "timeIntervalBuilder"
       [ testProperty "Verify TimeInterval construction correctness" propTimeIntervalBuilder
       ]
    ]
  ]

failure :: String -> Result
failure msg = failed
  { reason = msg
  , theException = Nothing
  }

propEncodeDecodeFullIso :: (Eq a,Show a,Show b) => (a -> b) -> (b -> a) -> a -> Result
propEncodeDecodeFullIso f g a =
  let fa = f a
      gfa = g fa
   in if gfa == a
        then succeeded
        else failure $ concat
          [ "x:       ", show a, "\n"
          , "f(x):    ", show fa, "\n"
          , "g(f(x)): ", show gfa, "\n"
          ]

propEncodeDecodeIso :: Eq a => (a -> b) -> (b -> Maybe a) -> a -> Bool
propEncodeDecodeIso f g a = g (f a) == Just a

propEncodeDecodeIsoSettings :: (Eq a,Show a,Show b,Show e)
  => (e -> a -> b) -> (e -> b -> Maybe a) -> e -> a -> Result
propEncodeDecodeIsoSettings f g e a =
  let fa = f e a
      gfa = g e fa
   in if gfa == Just a
        then succeeded
        else failure $ concat
          [ "env:     ", show e, "\n"
          , "x:       ", show a, "\n"
          , "f(x):    ", show fa, "\n"
          , "g(f(x)): ", show gfa, "\n"
          ]

parseMatch :: (Eq a, Show a) => Atto.Parser a -> Text -> a -> Assertion
parseMatch p t expected = do
  Atto.parseOnly (p <* Atto.endOfInput) t
  @?= Right expected

bsParseMatch :: (Eq a, Show a) => AttoBS.Parser a -> ByteString -> a -> Assertion
bsParseMatch p t expected = do
  AttoBS.parseOnly (p <* AttoBS.endOfInput) t
  @?= Right expected

timeOfDayParse :: Maybe Char -> Text -> TimeOfDay -> Assertion
timeOfDayParse m t expected =
  Atto.parseOnly (C.parser_HMS m <* Atto.endOfInput) t
  @?= Right expected

bsTimeOfDayParse :: Maybe Char -> ByteString -> TimeOfDay -> Assertion
bsTimeOfDayParse m t expected =
  AttoBS.parseOnly (C.parserUtf8_HMS m <* AttoBS.endOfInput) t
  @?= Right expected

timeOfDayBuilder :: SubsecondPrecision -> Maybe Char -> Text -> TimeOfDay -> Assertion
timeOfDayBuilder sp m expected tod =
  LText.toStrict (Builder.toLazyText (C.builder_HMS sp m tod))
  @?= expected

bsTimeOfDayBuilder :: SubsecondPrecision -> Maybe Char -> Text -> TimeOfDay -> Assertion
bsTimeOfDayBuilder sp m expected tod =
  LText.toStrict (Builder.toLazyText (C.builder_HMS sp m tod))
  @?= expected

dateParse :: Maybe Char -> Text -> Date -> Assertion
dateParse m t expected =
  Atto.parseOnly (C.parser_Ymd m <* Atto.endOfInput) t
  @?= Right expected

dateBuilder :: Maybe Char -> Text -> Date -> Assertion
dateBuilder m expected tod =
  LText.toStrict (Builder.toLazyText (C.builder_Ymd m tod))
  @?= expected

matchBuilder :: Text -> Builder -> Assertion
matchBuilder a b = LText.toStrict (Builder.toLazyText b) @?= a

propWithinInsideInterval :: TimeInterval -> Bool
propWithinInsideInterval ti@(TimeInterval t0 t1) = C.within t1 ti && C.within t0 ti

propWithinOutsideInterval :: RelatedTimes -> Bool
propWithinOutsideInterval (RelatedTimes t ti@(TimeInterval t0 t1))
  | t == t0 = discard
  | t == t1 = discard
  | t1 <= t0 = discard
  | t0 < (Time 0) = discard
  | t < (Time 0)  = discard
  | otherwise =
    let
      span = C.timeIntervalToTimespan ti
      tm = T.add span t
    in
      not $ C.within tm ti

propEncodeDecodeTimeInterval :: TimeInterval -> Bool
propEncodeDecodeTimeInterval ti@(TimeInterval t0 t1)
  | t0 < (Time 0) = discard
  | t0 >= t1 = discard
  | otherwise =
    let
      span = C.timeIntervalToTimespan ti
      tm = T.add span t0
    in
      t1 == tm

propSingletonBoundsEquals :: Time -> Bool
propSingletonBoundsEquals tm =
  let
    (TimeInterval (Time ti) (Time te)) = C.singleton tm
  in
    ti == te

propWidthVerifyBounds :: TimeInterval -> Bool
propWidthVerifyBounds ti@(TimeInterval (Time lower) (Time upper)) =
  let
    tiWidth = (getTimespan . C.width) ti
  in
    T.add lower tiWidth == upper && T.difference upper tiWidth == lower

propTimeIntervalBuilder :: Time -> Time -> Bool
propTimeIntervalBuilder  t0 t1 =
  let
    (TimeInterval ti te) = (C.timeIntervalBuilder t0 t1)
  in
    (getTime te) >= (getTime ti)

instance Arbitrary TimeOfDay where
  arbitrary = TimeOfDay
    <$> choose (0,23)
    <*> choose (0,59)
    -- never use leap seconds for property-based tests
    <*> choose (0,60000000000 - 1)

instance Arbitrary Date where
  arbitrary = Date
    <$> fmap Year (choose (1800,2100))
    <*> fmap Month (choose (0,11))
    <*> fmap DayOfMonth (choose (1,28))

instance Arbitrary Datetime where
  arbitrary = Datetime <$> arbitrary <*> arbitrary

-- instance Arbitrary UtcTime where
--   arbitrary = UtcTime
--     <$> fmap Day (choose (-100000,100000))
--     <*> choose (0,24 * 60 * 60 * 1000000000 - 1)

instance Arbitrary OffsetDatetime where
  arbitrary = OffsetDatetime
    <$> arbitrary
    <*> arbitrary

instance Arbitrary DatetimeFormat where
  arbitrary = DatetimeFormat
    <$> arbitrary
    <*> elements [Nothing, Just '/', Just ':', Just '-']
    <*> arbitrary

instance Arbitrary OffsetFormat where
  arbitrary = arbitraryBoundedEnum
  shrink = genericShrink

deriving instance Arbitrary Time

instance Arbitrary TimeInterval where
  arbitrary = do
    t0 <- arbitrary
    t1 <- suchThat arbitrary (>= t0)
    pure (TimeInterval t0 t1)

data RelatedTimes = RelatedTimes Time TimeInterval
  deriving (Show)

instance Arbitrary RelatedTimes where
  arbitrary = do
        ti@(TimeInterval t0 t1) <- arbitrary
        tm <- fmap Time (choose (getTime t0, getTime t1))
        pure $ RelatedTimes tm ti

instance Arbitrary Offset where
  arbitrary = fmap Offset (choose ((-24) * 60, 24 * 60))
