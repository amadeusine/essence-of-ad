{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
module VectorSpace where

import Prelude hiding ((.), id, curry, uncurry)
import Data.List
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)

import Common hiding (Scalable (..))

-- ------------------------------------------------------------------------

class (Fractional (Scalar a), Ord (Basis a), Additive a) => VectorSpace a where
  type Scalar a
  type Basis a
  scale :: Scalar a -> a -> a
  decompose :: a -> Map (Basis a) (Scalar a)
  basisValue :: Basis a -> a

linComb :: VectorSpace a => [(a, Scalar a)] -> a
linComb xs = foldl' (.+.) zero [scale s a | (a,s) <- xs]

compose :: VectorSpace a => Map (Basis a) (Scalar a) -> a
compose xs = linComb [(basisValue a, s) | (a,s) <- Map.toList xs]

instance VectorSpace Double where
  type Scalar Double = Double
  type Basis Double = ()
  scale = (*)
  decompose x = Map.singleton () x
  basisValue () = 1

instance (VectorSpace a, VectorSpace b, Scalar a ~ Scalar b) => VectorSpace (a, b) where
  type Scalar (a, b) = Scalar a
  type Basis (a, b) = Either (Basis a) (Basis b)
  scale s (a,b) = (scale s a, scale s b)
  decompose (a,b) = Map.mapKeysMonotonic Left (decompose a) `Map.union` Map.mapKeysMonotonic Right (decompose b)
  basisValue (Left x) = (basisValue x, zero)
  basisValue (Right x) = (zero, basisValue x)

-- ------------------------------------------------------------------------

newtype LinMap s a b = LinMap (Basis a -> b)

asFun :: (VectorSpace a, VectorSpace b, Scalar a ~ Scalar b) => (LinMap s a b) -> (a -> b)
asFun (LinMap f) x = linComb [(f b, s) | (b,s) <- Map.toList (decompose x)]

instance Category (LinMap s) where
  type Obj (LinMap s) a = (VectorSpace a, Scalar a ~ s)
  id = LinMap basisValue
  g . LinMap f = LinMap (asFun g . f)

instance Additive b => Additive (LinMap s a b) where
  zero = LinMap (const zero)
  LinMap f .+. LinMap g = LinMap (\x -> f x .+. g x)

instance Monoidal (LinMap s) where
  LinMap f >< LinMap g = LinMap h
    where
      h (Left a) = (f a, zero)
      h (Right b) = (zero, g b)
  monObj = ObjR

instance Cartesian (LinMap s) where
  exl = LinMap f
    where
      f (Left a) = basisValue a
      f (Right _b) = zero
  exr = LinMap f
    where
      f (Left _a) = zero
      f (Right b) = basisValue b
  dup = LinMap (\a -> (basisValue a, basisValue a))

instance Cocartesian (LinMap s) where
  inl = LinMap (\a -> (basisValue a, zero))
  inr = LinMap (\b -> (zero, basisValue b))
  jam = LinMap f
    where
      f (Left a) = basisValue a
      f (Right b) = basisValue b

-- ------------------------------------------------------------------------

-- | Dual vector space
newtype Dual a = Dual (LinMap (Scalar a) a (Scalar a))

-- Scalar a について Additive ではなく Num で計算しているので注意
instance VectorSpace a => Additive (Dual a) where
  zero = Dual (LinMap (const 0))
  Dual (LinMap f) .+. Dual (LinMap g) = Dual $ LinMap (\x -> f x + g x)

instance VectorSpace a => VectorSpace (Dual a) where
  type Scalar (Dual a) = Scalar a
  type Basis (Dual a) = Basis a
  scale s (Dual (LinMap f)) = Dual (LinMap ((s*) . f))
  decompose (Dual (LinMap f)) = Map.mapWithKey (\x _ -> f x) $ decompose (zero :: a)
  basisValue b = Dual (LinMap (\b' -> if b == b' then 1 else 0))

toDual :: VectorSpace a => a -> Dual a
toDual a = Dual $ LinMap $ \x -> Map.findWithDefault 0 x m
  where
    m = decompose a

toDualMap :: forall a b s. (VectorSpace a, VectorSpace b, Scalar a ~ s, Scalar b ~ s) => LinMap s a b -> LinMap s (Dual b) (Dual a)
toDualMap (LinMap f) = LinMap g
  where
    -- f :: Basis a -> b
    g :: Basis (Dual b) -> Dual a
    g b = Dual (LinMap h)
      where
        h :: Basis a -> s
        h = Map.findWithDefault 0 b . decompose . f

fromDual :: forall a. VectorSpace a => Dual a -> a
fromDual (Dual (LinMap f)) = compose $ Map.mapWithKey (\x _ -> f x) $ decompose (zero :: a)

fromDualMap :: forall a b s. (VectorSpace a, VectorSpace b, Scalar a ~ s, Scalar b ~ s) => LinMap s (Dual b) (Dual a) -> LinMap s a b
fromDualMap (LinMap f) = LinMap g
  where
    -- f :: Basis (Dual b) -> Dual a    
    g :: Basis a -> b
    g a = compose $ Map.mapWithKey (\b _ -> let Dual (LinMap (h :: Basis a -> s)) = f b in h a) $ decompose (zero :: b)

-- ------------------------------------------------------------------------

testDual = (asFun f (2,1) == 7, asFun f2 (2,1) == 7)
  where
    f :: LinMap Double (Double, Double) Double
    f = LinMap f'
      where
        f' (Left _) = 2
        f' (Right _) = 3
    f2 = fromDualMap (toDualMap f)

-- ------------------------------------------------------------------------

data a :⊗ b where
  TensorProd :: (Scalar a ~ s, Scalar b ~ s) => Map (Basis a, Basis b) s -> a :⊗ b

instance (VectorSpace a, VectorSpace b, Scalar a ~ Scalar b) => Additive (a :⊗ b) where
  zero = TensorProd $ Map.fromList $ do
    (a, _) <- Map.toList $ decompose (zero :: a)
    (b, _) <- Map.toList $ decompose (zero :: b)
    return ((a,b), 0)
  TensorProd m1 .+. TensorProd m2 = TensorProd $ Map.unionWith (+) m1 m2

instance (VectorSpace a, VectorSpace b, Scalar a ~ Scalar b) => VectorSpace (a :⊗ b) where
  type Scalar (a :⊗ b) = Scalar a
  type Basis (a :⊗ b) = (Basis a, Basis b)
  scale s (TensorProd m) = TensorProd $ Map.map (*s) m
  decompose (TensorProd m) = m
  basisValue ab = TensorProd $ Map.singleton ab 1

curry
  :: forall a b c s. (VectorSpace a, VectorSpace b, VectorSpace c, Scalar a ~ s, Scalar b ~ s, Scalar c ~ s)
  => LinMap a (a :⊗ b) c -> LinMap s a (LinMap s b c)
curry (LinMap f) = LinMap g
  where
    g :: Basis a -> LinMap s b c
    g ba = LinMap (\bb -> f (ba,bb))

uncurry
  :: forall a b c s. (VectorSpace a, VectorSpace b, VectorSpace c, Scalar a ~ s, Scalar b ~ s, Scalar c ~ s)
  => LinMap s a (LinMap s b c) -> LinMap a (a :⊗ b) c
uncurry (LinMap f) = LinMap g
  where
    g (ba,bb) =
      case f ba of
        LinMap h -> h bb

mapTensor
  :: forall a b c d s.
     ( VectorSpace a, VectorSpace b, VectorSpace c, VectorSpace d
     , Scalar a ~ s, Scalar b ~ s, Scalar c ~ s, Scalar d ~ s
     )
  => LinMap s a b -> LinMap s c d -> LinMap s (a :⊗ c) (b :⊗ d)
mapTensor (LinMap f) (LinMap g) = LinMap h
  where
    h :: Basis (a :⊗ c) -> (b :⊗ d)
    h (ba, bc) = TensorProd m
      where
        m1 :: Map (Basis b) s
        m1 = decompose (f ba)
        m2 :: Map (Basis d) s
        m2 = decompose (g bc)
        m :: Map (Basis (b :⊗ d)) s
        m = Map.fromList [((bb,bd), s1*s2) | (bb, s1) <- Map.toList m1, (bd, s2) <- Map.toList m2]
