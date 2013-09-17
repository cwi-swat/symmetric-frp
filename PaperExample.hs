-- | The example from the paper
{-# LANGUAGE TupleSections, ViewPatterns, NoMonomorphismRestriction #-}
module PaperExample where

import Control.Monad.State.Lazy
import Control.SFRP
import Data.Set hiding (map,filter)
import Prelude hiding (null,map,filter,filter,until,repeat,cycle,scanl,span,break,tail )
import qualified Prelude as P
import Data.Maybe
import SDLSFRP
import Control.Monad
import qualified Data.Set as Set


mdown :: React GUIEv GUIEv
mdown = exper (MouseDown Request) 

mouseDown :: React GUIEv (Set MouseBtn)
mouseDown  = exper (MouseDown Request) >>= get
  where get (MouseDown (Occurred s)) = return s

-- stuff implicit in paper:
mouseUp    = exper (MouseUp Request) >>= get
  where get (MouseUp (Occurred t)) = return t
mouseMove  = exper (MouseMove Request) >>= get
  where get (MouseMove (Occurred t)) = return t
deltaTime  = exper (DeltaTime Request) >>= get
  where get (DeltaTime (Occurred t)) = return t


data EvInt = UpInt (Event Int) deriving (Eq,Ord)
getInt :: React EvInt Int
getInt = exper (UpInt Request) >>= get
  where get (UpInt (Occurred i)) = return i

updateMinMax :: Int -> Int -> Sig EvInt a (Int,Int)
updateMinMax mi mx = do i <- waitFor getInt; return (up i) where
   up i = (min mi i, max mx i)

data Void

untilR :: Ord e => Sig e a Void -> Sig e Void b -> Sig e a b
untilR a b = do (_, End b) <- pure (\x y -> x) <*> a <*> b
                return b

constant = pure
always = pure
green = head colors
red = green
orange = green

traffic :: Sig GUIEv Color Void
traffic = 
  do always green `until'` rightClick
     l <- always orange `until'` (rightClick `before` leftClick)
     if l then traffic else always red
before :: React a x -> React a y -> React Bool

until' :: Ord e => Sig e a r -> React e b -> Sig e a b
until' a b = fmap (\(_,Done a) -> a) $ a `until` b 

{-
ding2 :: Sig EvInt Int Void
ding2 = evalStateT di (0,0) where
  di = do (mi,_)  <- get
          lift  constant mi        `untilR` update
          (_,mx) <- get
          lift $ constant mx        `untilR` update
          (mi,mx) <- get
          lift $ constant (mi + mx) `untilR` update
          di

  update = do i <- lift $ waitFor (getInt)
              (mi,mx) <- get
              put (min i mi, max i mx)

ding :: Int -> Int -> Sig EvInt Int Void
ding mi mx = do  (mi,mx) <- constant mi      `untilR` updateMinMax mi mx
                 (mi,mx) <- constant mx      `untilR` updateMinMax mi mx
                 (mi,mx) <- constant (mi+mx) `untilR` updateMinMax mi mx
                 ding mi mx

-}
tryWait t = exper (TryWait t Request) >>= get
  where get (TryWait _ (Occurred t)) = return t


sameClick :: Reactg Bool

sameClick =  mouseDown >>= (\pressed   ->
             mouseDown >>= (\pressed2  ->
             return (pressed == pressed2)))


sameClick2 = do  pressed   <-  mouseDown
                 pressed2  <-  mouseDown
                 return (pressed == pressed2)

clickOn :: MouseBtn -> Reactg ()
clickOn b = do  bs <- mouseDown
                if (b `member` bs) then return () else clickOn b

leftClick    = clickOn MLeft
middleClick  = clickOn MMiddle
rightClick   = clickOn MRight

--implicit in paper
releaseOf :: MouseBtn -> Reactg ()
releaseOf b = do  bs <- mouseUp
                  if (b `member` bs) then return () else releaseOf b
leftUp    = releaseOf MLeft
middleUp  = releaseOf MMiddle
rightUp   = releaseOf MRight

before :: Reactg a -> Reactg b -> Reactg Bool
before a b = do  (a',b') <- first a b
                 case (done a', done b') of
                   (Just _, Nothing)  -> return True
                   _                  -> return False

doubler :: Reactg ()
doubler = do  rightClick
              r <- rightClick `before` sleep 0.2
              if r then return () else doubler



cycleColor :: Sigg Color Int
cycleColor = cc colors 0 where
  cc (h:t) i = 
    do  emit h
        r <- waitFor (before middleClick rightClick)
        if r then cc t (i+1) else return i


mousePos :: Sigg Point ()
mousePos = repeat mouseMove

curRect :: Point -> Sigg Rect ()
curRect p1 = map (Rect p1) mousePos

-- data Rect    = Rect {leftup :: Point, rightdown :: Point}


elapsed :: Sigg Time ()
elapsed = scanl (+) 0 (repeat deltaTime)

wiggleRect :: Rect -> Sigg Rect ()
wiggleRect (Rect lu rd) = map rectAtTime elapsed
  where rectAtTime t =  Rect (lu +. dx) (rd +. dx)
                        where dx = (sin (t * 5) * 15, 0)

(x,y) +. (x',y') = (x + x', y + y')


posInside :: Rect -> Sigg Point y -> Reactg (Maybe Point)
posInside r = find (`inside` r)

inside :: Point -> Rect -> Bool
(x,y) `inside` (normalize -> Rect (lx,uy) (rx,dy)) = 
  x >= lx && x <= rx && y >= uy && y <= dy


firstPoint :: Reactg (Maybe Point) 
firstPoint = mousePos `at` leftClick


completeRect :: Point -> Sigg Rect (Maybe Rect)
completeRect p1 = do  (r,_) <- curRect p1 `until` leftUp
                      return (cur r)

defineRect :: Sigg Rect Rect
defineRect = do  Just p1  <-  waitFor firstPoint
                 r <- completeRect p1 -- slight difference with paper: if the user does not move the mouse the pattern match will fail (this would define an empty rectangle) here we fix this.
                 case r of 
                   Just r -> return r
                   Nothing -> defineRect


chooseBoxColor :: Rect -> Sigg Box ()
chooseBoxColor r = 
  do  pure Box <*> wiggleRect r <*> cycleColor
      return ()


drClickOn :: Rect -> Reactg (Maybe Point)
drClickOn r = 
  posInside r (mousePos `indexBy` repeat doubler)


box :: Sigg Box ()
box = do  r <- map setColor defineRect
          chooseBoxColor r
          waitFor (drClickOn r)
          return ()
  where setColor r = Box r (head colors)


boxes :: Sigg [Box] ()
boxes =  parList (spawn box)


type Reactg = React GUIEv

sleep :: Time -> React GUIEv ()
sleep t = do  t' <- tryWait t
              if t' == t then return () else sleep (t - t')

type Sigg     = Sig    GUIEv
type ISigg    = ISig  GUIEv

-- implicit in paper
colors = P.cycle [Color 1 0 0 , Color 0 1 0 , Color 0 0 1 , Color 1 1 0, Color 0 1 1 , Color 1 0 1, Color 0 1 1]



