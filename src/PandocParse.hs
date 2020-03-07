{-# LANGUAGE OverloadedStrings #-}

module PandocParse where

import Text.Pandoc
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.Text.Lazy as TL
import qualified Data.Text as T
import qualified Data.Vector as V
import qualified Data.HashMap.Strict as HM
import Data.Aeson.Types
import Data.Aeson
import Data.Scientific
import Data.Maybe (fromMaybe)
import Types

readZettel :: PandocMonad m => FilePath -> m Pandoc
readZettel f = do
  content <- E.decodeUtf8 <$> readFileLazy f
  let extension = enableExtension Ext_yaml_metadata_block emptyExtensions
  readMarkdown (def {readerExtensions = extension }) (TL.toStrict content)

createZettel :: PandocMonad m => Pandoc -> m Zettel
createZettel p@(Pandoc m _) = do
  title <- writePlain def (Pandoc nullMeta [Plain (docTitle m)])
  author <- writePlain def (Pandoc nullMeta [Plain (concat $ docAuthors m)])
  tags <- writePlain def (Pandoc nullMeta [Plain (concat $ docTags m)])
  zettel <- writeMarkdown def p
  let res = lookupMeta "connections" m
  connections <- case res of
        Nothing -> return []
        (Just (MetaBlocks r)) -> do
          str <- writePlain def (Pandoc nullMeta r)
          return $ toConnections (fromMaybe (Array V.empty) . decode $ E.encodeUtf8 (TL.fromStrict str))
  timestamp <- getCurrentTime
  return (Zettel {
    getId = ZID 0,
    getTimestamp = T.pack . show $ timestamp,
    getTitle = title,
    getAuthors = T.splitOn "," author,
    getZettel = zettel,
    getTags = T.splitOn "," tags,
    getConnections = connections
                 })

toConnections :: Value -> [Connection]
toConnections (Array l) = V.toList $ V.map toConnection l

toConnection :: Value -> Connection
toConnection (Object m) =
  let i = fromMaybe (-1) . toBoundedInteger . fromNumber . fromMaybe (Number 0) $ "id" `HM.lookup` m
      reason = fromString . fromMaybe "" $ "reason" `HM.lookup` m
   in Connection {
    getCID = ZID i,
    getDesc = reason
                 }
  where
    fromNumber (Number n) = n
    fromString (String s) = s

docTags :: Meta -> [[Inline]]
docTags meta =
  case lookupMeta "tags" meta of
        Just (MetaString s)    -> [[Str s]]
        Just (MetaInlines ils) -> [ils]
        Just (MetaList   ms)   -> [ils | MetaInlines ils <- ms] ++
                                  [ils | MetaBlocks [Plain ils] <- ms] ++
                                  [ils | MetaBlocks [Para ils]  <- ms] ++
                                  [[Str x] | MetaString x <- ms]
        _                      -> []

