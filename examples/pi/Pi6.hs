{-# LANGUAGE TemplateHaskell,BangPatterns #-}
module Main where

import Remote

import Data.Ratio
import Debug.Trace
import Control.Monad
import Prelude hiding (break)
import Data.List hiding (break)
import Data.IORef
import Data.Array.IO
import Data.Array
import Control.Monad.State

type Number = Double

data Seq = Seq {k::Int, x::Number, base::Int, q::Array Int Number, break::Bool}

--shold maybe be Integer to allow for really big ranges
getSeq :: Int -> Int -> [Number]
getSeq offset thebase = let
                    digits = 64::Int
                    seqSetup :: Seq -> Int -> Number -> (Seq, Number)
                    seqSetup s j _ = 
                                     let dj =  (k s `mod` base s)
                                         news = s {k = (k s - dj) `div` fromIntegral (base s), x = x s + (fromIntegral dj * ((q s) ! (j+1)))}     
                                      in
                                        (news,fromIntegral dj)
                    seqContinue :: Seq -> Int -> Number -> (Seq, Number)
                    seqContinue s j dj = 
                                     if break s
                                        then (s,dj)
                                        else 
                                               let newdj = dj+1
                                                   newx = x s + (q s) ! (j+1)
                                               in
                                               if newdj < fromIntegral (base s)
                                                  then (s {x=newx,break=True},newdj)
                                                  else (s {x = newx - if j==0 then 1 else (q s) ! j},0)

                    initialState base = let q = array (0,digits*2) [(i,v) | i <- [0..digits*2], let v = if i == 0 then 1 else ((q ! ((i)-1))/fromIntegral base)]
                                        in Seq {k=fromIntegral offset,x=0,break=False,base=base,q=q}
                    theseq base = let
                        first :: (Int,[Number],Seq)
                        first = foldl' (\(n,li,s) _ -> let (news,r) = seqSetup s n 0
                                                       in (n+1,r:li,news)) (0,[],initialState base) [0..digits]
                        second :: [Number] -> Seq -> (Int,[Number],Seq)
                        second d s = foldl' (\(n,li,s) dj -> let (news,r) = seqContinue s n dj
                                                             in (n+1,r:li,news)) (0,[],s {break=False}) d
                        in let (_,firstd,firsts) = first
                               therest1 :: [([Number],Seq)]
                               therest1 = iterate (\(d,s) -> let (_,newd,news) = second (reverse d) s in (newd,news)) (firstd,firsts)
                               therest :: [Number]
                               therest = map (\(_,s) -> x s) therest1
                           in therest
                        in (theseq thebase)

pairs :: Int -> [(Number,Number)]
pairs offset = zip (getSeq offset 2) (getSeq offset 3)

countPairs :: Int -> Int -> (Int,Int)
countPairs offset count = let range = take count $ pairs offset
                              numout = foldl' (\i coord -> if outCircle coord then i+1 else i) 0 range
                           in (count-numout,numout)
       where
         outCircle (x,y) = let fx=x-0.5 
                               fy=y-0.5
                       in fx*fx + fy*fy > 0.25

mapper :: Int -> Int -> ProcessId -> ProcessM ()
mapper count offset master = let (numin,numout) = countPairs offset count in
                                        send master (numin,numout)

remotable ['mapper]                                      

longdiv :: Integer -> Integer -> Integer -> String
longdiv _ 0 _ = "<inf>"
longdiv numer denom places = let attempt = numer `div` denom in
                                if places==0
                                   then "" 
                                   else shows attempt (longdiv2 (numer - attempt*denom) denom (places -1))
     where longdiv2 numer denom places | numer `rem` denom == 0 = "0"
                                       | otherwise = longdiv (numer * 10) denom places

initialProcess "SLAVE" = do
           receiveWait []

initialProcess "MASTER" = do
           peers <- getPeers
           let slaves = findPeerByRole peers "SLAVE"
           let interval = 1000000
           mypid <- getSelfPid
           say "Starting..."
           mapM_ (\(offset,nid) -> 
                   do say $ "Telling slave " ++ show nid ++ " to look at range " ++ show offset ++ ".." ++ show (offset+interval)
                      spawn nid (mapper__closure (interval-1) offset mypid)) (zip [0,interval..] slaves)
           (x,y) <- receiveLoop (0,0) (length slaves)
           let est = estimatePi (fromIntegral x) (fromIntegral y)
           say $ "Done: " ++ longdiv (numerator est) (denominator est) 100
      where estimatePi ni no | ni+no==0 = 0
                             | otherwise = (4 * ni) % (ni+no)
            receiveLoop a 0 = return a
            receiveLoop (numIn,numOut) n = 
                  let 
                     resultMatch = match (\(x,y) -> return (x::Int,y::Int))
                  in do (newin,newout) <- receiveWait [resultMatch]
                        let x = numIn + newin
                        let y = numOut + newout
                        -- say $ longdiv (numerator $ estimatePi x y) (denominator $ estimatePi x y) 10
                        receiveLoop (x,y) (n-1)

initialProcess _ = error "Role must be SLAVE or MASTER"

main = remoteInit (Just "config") [Main.__remoteCallMetaData] initialProcess


