module Steps where

import Inputs (..)
import Game (..)
import Geo (..)
import Core (..)

import Debug

{-- Part 3: Update the game ---------------------------------------------------

How does the game step from one state to another based on user input?

Task: redefine `stepGame` to use the UserInput and GameState
      you defined in parts 1 and 2. Maybe use some helper functions
      to break up the work, stepping smaller parts of the game.

------------------------------------------------------------------------------}

mouseStep : MouseInput -> GameState -> GameState
mouseStep ({drag, mouse} as mouseInput) gameState =
  let boat = gameState.boat
      center = case drag of
        Just (x',y') -> let (x,y) = mouse in sub (floatify (x - x', y' - y)) boat.center
        Nothing      -> boat.center 
  in
    { gameState | boat <- { boat | center <- center } }

tackTargetReached : Boat -> Maybe Float -> Bool
tackTargetReached boat targetMaybe = 
  case (targetMaybe, boat.controlMode) of
    (Just target, FixedWindAngle) -> abs (target - boat.windAngle) < 0.1
    (Just target, FixedDirection) -> abs (target - boat.direction) < 0.1
    (Nothing, _)                  -> False

getTackTarget : Boat -> Bool -> Maybe Float
getTackTarget boat spaceKey =
  case (boat.tackTarget, spaceKey) of
    -- target en cours
    (Just _, _) -> 
      -- si direction cible atteinte, on arrête le virement
      if tackTargetReached boat boat.tackTarget then Nothing else boat.tackTarget
    -- si touche espace pressée, on défini la cible
    (Nothing, True) -> 
      case boat.controlMode of
        FixedWindAngle -> Just -boat.windAngle
        FixedDirection -> Just (ensure360 (boat.windOrigin - boat.windAngle))
    -- sinon, pas de cible
    (Nothing, False) -> Nothing



getTurn : Maybe Float -> Boat -> UserArrows -> Bool -> Float
getTurn tackTarget boat arrows fineTurn =
  case (tackTarget, boat.controlMode, arrows.x, arrows.y) of 
    -- virement en cours
    (Just target, _, _, _) -> 
      case boat.controlMode of 
        FixedDirection -> 
          let maxTurn = minimum [2, (abs (boat.direction - target))]
          in
            if ensure360 (boat.direction - target) > 180 then maxTurn else -maxTurn
        FixedWindAngle -> 
          let maxTurn = minimum [2, (abs (boat.windAngle - target))]
          in
            if target > 90 || (target < 0 && target >= -90) then -maxTurn else maxTurn
    -- pas de virement ni de touche flèche, donc contrôle auto
    (Nothing, FixedDirection, 0, 0) -> 0
    (Nothing, FixedWindAngle, 0, 0) -> (boat.windOrigin + boat.windAngle) - boat.direction
    -- changement de direction via touche flèche
    (Nothing, _, x, y) -> if fineTurn then x else x * 3

keysForBoatStep : KeyboardInput -> Boat -> Boat
keysForBoatStep ({arrows, lockAngle, tack, fineTurn}) boat =
  let forceTurn = arrows.x /= 0 
      tackTarget = if forceTurn then Nothing else getTackTarget boat tack
      turn = getTurn tackTarget boat arrows fineTurn
      direction = ensure360 <| boat.direction + turn
      windAngle = angleToWind direction boat.windOrigin
      turnedBoat = { boat | direction <- direction,
                            windAngle <- windAngle }
      tackTargetAfterTurn = if tackTargetReached turnedBoat tackTarget then Nothing else tackTarget
      controlMode = if | forceTurn -> FixedDirection
                       | arrows.y > 0 || lockAngle -> FixedWindAngle
                       | otherwise -> turnedBoat.controlMode
  in 
    { turnedBoat | controlMode <- controlMode,
                   tackTarget <- tackTargetAfterTurn }

keysStep : KeyboardInput -> GameState -> GameState
keysStep keyboardInput gameState =
  let boatUpdated = keysForBoatStep keyboardInput gameState.boat
  in  { gameState | boat <- boatUpdated }

gatePassedInX : Gate -> (Point,Point) -> Bool
gatePassedInX gate ((x,y),(x',y')) =
  let a = (y - y') / (x - x')
      b = y - a * x
      xGate = (gate.y - b) / a
  in
    (abs xGate) <= gate.width / 2

gatePassedFromNorth : Gate -> (Point,Point) -> Bool
gatePassedFromNorth gate (p,p') =
  (snd p) > gate.y && (snd p') <= gate.y && (gatePassedInX gate (p,p'))

gatePassedFromSouth : Gate -> (Point,Point) -> Bool
gatePassedFromSouth gate (p,p') =
  (snd p) < gate.y && (snd p') >= gate.y && (gatePassedInX gate (p,p'))

getPassedGates : Boat -> Time -> Course -> (Point,Point) -> [Time]
getPassedGates boat timestamp ({upwind, downwind, laps}) step =
  case (findNextGate boat course.laps) of
    -- ligne de départ
    Just StartLine -> if | gatePassedFromSouth downwind step -> timestamp :: boat.passedGates 
                         | otherwise                         -> boat.passedGates
    -- bouée au vent
    Just Upwind    -> if | gatePassedFromSouth upwind step   -> timestamp :: boat.passedGates 
                         | gatePassedFromSouth downwind step -> tail boat.passedGates
                         | otherwise                         -> boat.passedGates
    -- bouée sous le vent
    Just Downwind  -> if | gatePassedFromNorth downwind step -> timestamp :: boat.passedGates 
                         | gatePassedFromNorth upwind step   -> tail boat.passedGates 
                         | otherwise                         -> boat.passedGates
    -- arrivée déjà franchie
    Nothing        -> boat.passedGates

getGatesMarks : Course -> [Point]
getGatesMarks course =
  [
    (course.upwind.width / -2, course.upwind.y),
    (course.upwind.width / 2, course.upwind.y),
    (course.downwind.width / -2, course.downwind.y),
    (course.downwind.width / 2, course.downwind.y)
  ]

isStuck : Point -> GameState -> Bool
isStuck p gameState =
  let gatesMarks = getGatesMarks gameState.course
      stuckOnMark = any (\m -> distance m p <= gameState.course.markRadius) gatesMarks
      outOfBounds = not (inBox p gameState.course.bounds)
      onIsland = any (\i -> distance i.location p <= i.radius) gameState.course.islands
  in 
    outOfBounds || stuckOnMark || onIsland

getCenterAfterMove : Point -> Point -> Point -> (Float,Float) -> (Point)
getCenterAfterMove (x,y) (x',y') (cx,cy) (w,h) =
  let refocus n n' c d margin = 
        let min = c - (d / 2)
            mmin = min + margin
            max = c + (d / 2)
            mmax = max - margin
        in
          if | n < min || n > max -> c
             | n < mmin           -> if n' < n then c - (n - n') else c
             | n > mmax           -> if n' > n then c + (n' - n) else c
             | n' < mmin          -> c - (n - n')
             | n' > mmax          -> c + (n' - n)
             | otherwise          -> c
  in
    (refocus x x' cx w (w * 0.2), refocus y y' cy h (h * 0.4))

moveBoat : Time -> Float -> GameState -> (Int,Int) -> Boat -> Boat
moveBoat now delta gameState dimensions boat =
  let {position, direction, velocity, windAngle, passedGates} = boat
      newVelocity = boatVelocity boat.windAngle velocity
      nextPosition = movePoint position delta newVelocity direction
      stuck = isStuck nextPosition gameState
      newPosition = if stuck then position else nextPosition
      newPassedGates = if gameState.countdown <= 0
        then getPassedGates boat now gameState.course (position, newPosition)
        else boat.passedGates
      newCenter = getCenterAfterMove position newPosition boat.center (floatify dimensions)
  in
      { boat | position <- newPosition,
               velocity <- if stuck then 0 else newVelocity,
               center <- newCenter,
               passedGates <- newPassedGates }

moveStep : Time -> Float -> (Int,Int) -> GameState -> GameState
moveStep now delta dims gameState =
  let boatMoved = moveBoat now delta gameState dims gameState.boat
  in  { gameState | boat <- boatMoved }

--randInWindow : Int -> Int -> Int -> Int
--randInWindow t w i =
--    ((t ^ i) + (t * i * 1000)) `mod` w

--spawnGustX : Int -> Float -> Int -> Int
--spawnGustX t w spawnIndex =
--  (randInWindow t (round w) spawnIndex) - (round (w/2))

--spawnGustY : Int -> Float -> Int -> Int
--spawnGustY t h spawnIndex =
--  (randInWindow t (round h) spawnIndex)

--spawnGust : Time -> (Point,Point) -> Int -> Gust
--spawnGust timestamp ((right,top),(left,bottom)) spawnIndex =
--  let 
--    t = round timestamp
--    x = spawnGustX t (right - left) (spawnIndex + 1)
--    y = if spawnIndex == 0 then (round top) - 1 else spawnGustY t (top - bottom) spawnIndex
--    radius = (randInWindow t 100 (spawnIndex + 1)) + 100 |> toFloat 
--    speedImpact = 0
--    originDelta = (randInWindow t 20 (spawnIndex + 1)) - 10 |> toFloat
--  in
--    { position = floatify (x,y), radius = radius, speedImpact = speedImpact, originDelta = originDelta }

--gustInBounds : (Point,Point) -> Gust -> Bool
--gustInBounds bounds gust =
--  inBox gust.position bounds

--updateGusts : Time -> Float -> (Point, Point) -> Wind -> [Gust]
--updateGusts timestamp delta bounds wind = 
--  let 
--    moveGust w g = { g | position <- (movePoint g.position delta w.speed (ensure360 (180 + wind.origin + g.originDelta))) }
--    gusts = filter (gustInBounds bounds) wind.gusts |> map (moveGust wind)
--  in
--    if | (isEmpty wind.gusts) -> map (spawnGust timestamp bounds) [1..wind.gustsCount]
--       | (length gusts < wind.gustsCount) -> (spawnGust timestamp bounds 0) :: gusts 
--       | otherwise -> gusts

updateWindForBoat : Wind -> Boat -> Boat
updateWindForBoat wind boat =
  let
    gustsOnBoat : [Gust]
    gustsOnBoat = filter (\g -> (distance boat.position g.position) <= g.radius) wind.gusts
      |> sortBy .speedImpact |> reverse
    windOrigin = if (isEmpty gustsOnBoat) then 
      wind.origin 
    else 
      let 
        gust = head gustsOnBoat
        factor = minimum [(gust.radius - (distance boat.position gust.position)) / (gust.radius * 0.1), 1]
        newDelta = gust.originDelta * factor
      in
        ensure360 <| wind.origin + newDelta
  in
    { boat | windOrigin <- windOrigin }

windStep : Float -> Time -> GameState -> GameState
windStep delta now ({wind, boat} as gameState) =
  let o1 = cos (inSeconds now / 8) * 10
      o2 = cos (inSeconds now / 5) * 5
      newOrigin = o1 + o2 |> ensure360
      --newGusts = updateGusts now delta gameState.course.bounds wind
      newWind = { wind | origin <- newOrigin }
      boatWithWind = updateWindForBoat wind boat
  in { gameState | wind <- newWind,
                   boat <- boatWithWind }

raceInputStep : RaceInput -> GameState -> GameState
raceInputStep {now,startTime,course,opponents,leaderboard} gameState =
  { gameState | opponents <- opponents,
                course <- maybe gameState.course id course,
                leaderboard <- leaderboard,
                countdown <- startTime - now }

stepGame : Input -> GameState -> GameState
stepGame input gameState =
  mouseStep input.mouseInput 
    <| moveStep input.raceInput.now input.delta input.windowInput 
    <| keysStep input.keyboardInput
    <| windStep input.delta input.raceInput.now
    <| raceInputStep input.raceInput gameState
