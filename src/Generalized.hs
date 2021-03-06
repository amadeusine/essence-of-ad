{-# OPTIONS_GHC -Wall #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
module Generalized
  ( module Base

  , D (..)
  , unD
  , linearD

  , Cont (..)
  , cont

  , Dual (..)
  , unDual

  , Dual' (..)
  , unDual'
  , asDual'

  , Begin (..)
  , begin
  ) where

import Prelude hiding ((.), id, zipWith, unzip)

import Data.Functor.Rep

import Base

-- ------------------------------------------------------------------------

newtype D k a b = D (a -> (b, a `k` b))

unD :: D k a b -> (a -> (b, a `k` b))
unD (D f) = f

linearD :: (a -> b) -> (a `k` b) -> D k a b
linearD f f' = D (\a -> (f a, f'))

instance Category k => Category (D k) where
  type Obj (D k) a = (Obj k a, Additive a)
  id = linearD id id
  -- D g . D f = D (\a -> let (b, f') = f a; (c, g') = g b in (c, g' . f'))
  D g . D f = D h
    where
      h a = (c, g' . f')
        where
          (b, f') = f a
          (c, g') = g b

instance Monoidal k => Monoidal (D k) where
  -- D f >< D g = D (\(a,b) -> let (c, f') = f a; (d, g') = g b in ((c,d), f' >< g'))
  D f >< D g = D h
    where
      h (a,b) = ((c,d), f' >< g')
        where
          (c, f') = f a
          (d, g') = g b

  monObj :: forall a b. (Obj (D k) a, Obj (D k) b) => ObjR (D k) (a, b)
  monObj = case monObj :: ObjR k (a, b) of ObjR -> ObjR

instance Cartesian k => Cartesian (D k) where
  exl = linearD exl exl
  exr = linearD exr exr
  dup = linearD dup dup

instance Cocartesian k => Cocartesian (D k) where
  inl = linearD inlF inl
  inr = linearD inrF inr
  jam = linearD jamF jam

-- 論文だと Scalable k s しか仮定してないけど、
-- - (*) を使っているので Num s が必要
-- - (▽) を使っているので Cocartesian k が必要
-- - Obj (D k) s のために Additive s が必要
instance (Cocartesian k, Scalable k s, Additive s, Num s) => NumCat (D k) s where
  -- 論文では negateC = linearD negateC negateC と定義していたが、
  -- こっちの定義なら NumCat k s が不要で、適切ではないか?
  -- NumCat の定義には mulC の定義が必要なので (->⁺) のインスタンスを定義できない。
  negateC = linearD negateC (scale (-1))

  -- 論文では addC = linearD addC addC と定義していたが、
  -- こっちの定義なら NumCat k s が不要で、適切ではないか?
  -- NumCat の定義には mulC の定義が必要なので (->⁺) のインスタンスを定義できない。
  addC = linearD addC jam

  -- mulC = D (\(a,b) -> (a * b, scale b ▽ scale a))
  mulC :: forall. Obj (D k) s => D k (s, s) s
  mulC = case monObj :: ObjR k (s, s) of
           ObjR -> D (\(a,b) -> (a * b, scale b ▽ scale a))

-- 論文では定義が省略されていた
instance (Scalable k s, Additive s, Floating s) => FloatingCat (D k) s where
  sinC = D (\a -> (sin a, scale (cos a)))
  cosC = D (\a -> (cos a, scale (- sin a)))
  expC = D (\a -> let e = exp a in (e, scale e))

second :: (Monoidal k, Obj k a, Obj k b, Obj k d) => (b `k` d) -> ((a,b) `k` (a,d))
second g = id >< g

instance (MonoidalI k h, Zip h, forall a. (Obj k a, Additive a) => Additive (h a)) => MonoidalI (D k) h where
  crossI fs = D (second crossI . unzip . crossI (fmap unD fs))

  monObjI :: forall a. (Obj (D k) a) => ObjR (D k) (h a)
  monObjI = case monObjI :: ObjR k (h a) of ObjR -> ObjR

instance (CartesianI (->) h, CartesianI k h, Zip h, forall a. (Obj k a, Additive a) => Additive (h a)) => CartesianI (D k) h where
  -- 論文では linearD exI exI となっていたが間違い
  exI = zipWith linearD exI exI

  -- 論文では zipWith linearD replI replI となっていたが間違い
  replI = linearD replI replI

-- "Representable h" and "Eq (Rep h)" are for inIF.
-- "Foldable h" is for sum.
instance (CocartesianI k h, Zip h, Representable h, Eq (Rep h), forall a. (Obj k a, Additive a) => Additive (h a), Foldable h) => CocartesianI (D k) h where
  inI = zipWith linearD inIF inI
  jamI = linearD jamIF jamI

-- ------------------------------------------------------------------------

newtype Cont r k a b = Cont ((b `k` r) -> (a `k` r))

cont :: (Category k, Obj k a, Obj k b, Obj k r) => (a `k` b) -> Cont r k a b
cont f = Cont (. f)

instance (Category k, Obj k r) => Category (Cont r k) where
  type Obj (Cont r k) a = Obj k a

  id = Cont id
{-
  cont id = Cont (. id) = Cont id
-}

  Cont g . Cont f = Cont (f . g)
{-
  Cont (. g) . Cont (. f)
= cont g . cont f
= {- cont is expected to be a functor -}
  cont (g . f)
= Cont (. (g . f))
= Cont (\h -> h . g . f)
= Cont ((. f) . (. g))
-}

-- 論文だと instance Monoidal k => Monoidal (Cont r k) だけど、
-- join/unjoin を使っているので Cocartesian k が必要
instance (Cocartesian k, Obj k r) => Monoidal (Cont r k) where
  -- Cont f >< Cont g = Cont (join . (f >< g) . unjoin)
  (><) :: forall a b c d. (Obj (Cont r k) a, Obj (Cont r k) b, Obj (Cont r k) c, Obj (Cont r k) d) =>
          Cont r k a b -> Cont r k c d -> Cont r k (a, c) (b, d)
  Cont f >< Cont g =
    case (monObj :: ObjR k (a, c), monObj :: ObjR k (b, d), monObj :: ObjR k (r, r)) of
      (ObjR, ObjR, ObjR) -> Cont (join . (f >< g) . unjoin)
{-
  Cont (. f) >< Cont (. g)
= cont f >< cont g
= {- cont is expected to preserve (><) -}
  cont (f >< g)
= Cont (. (f >< g))
= Cont (\(h :: (b,d) `k` r) -> h . (f >< g))
= Cont (\(h :: (b,d) `k` r) -> ((h . inl) ▽ (h . inr)) . (f >< g))
= Cont (\(h :: (b,d) `k` r) -> (h . inl . f) ▽ (h . inr . g))
= Cont (\(h :: (b,d) `k` r) -> join (h . inl . f, h . inr . g))
= Cont (join . (\(h :: (b,d) `k` r) -> (h . inl . f, h . inr . g)))
= Cont (join . (\(h :: (b,d) `k` r) -> (h . inl . f, h . inr . g)))
= Cont (join . (\(h1, h2) -> (h1 . f, h2 . g)) . unjoin)
= Cont (join . ((. f) >< (. g)) . unjoin)
-}

  monObj :: forall a b. (Obj (Cont r k) a, Obj (Cont r k) b) => ObjR (Cont r k) (a, b)
  monObj = case monObj :: ObjR k (a, b) of ObjR -> ObjR

-- 論文だと instance Cartesian k => Cartesian (Cont r k) だけど、
-- - 論文で使っていた inl/inr/jam の代わりにinlF/inrF/jamF を使う必要があり、
--   そのために Additive (k a r) が必要になる。
-- - join/unjoin のために、 Cartesian k ではなく Cocartesian k が必要。
--   また上述の Monoidal の条件としても Cocartesian k は必要。
-- - Cartesian は contを使った定義だと必要だが、現在の定義だと実は不要。
instance (Cocartesian k, Cartesian k, Obj k r, forall a. Obj k a => Additive (k a r)) => Cartesian (Cont r k) where
  -- exl = Cont (join . inl)
  exl :: forall a b. (Obj (Cont r k) a, Obj (Cont r k) b) => Cont r k (a, b) a
  exl = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, b)) of
          (ObjR, ObjR) -> Cont (join . inlF)
{-
If (,) is biproduct in k, then:
  cont exl
= Cont (. exl)
= Cont (\f -> f . exl)
= Cont (\f -> f . (id ▽ zero))
= Cont (\f -> f ▽ zero)
= Cont (\f -> join (f, zero))
= Cont (join . inF)
-}

  -- exr = Cont (join . inr)
  exr :: forall a b. (Obj (Cont r k) a, Obj (Cont r k) b) => Cont r k (a, b) b
  exr = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, b)) of
          (ObjR, ObjR) -> Cont (join . inrF)
{-
If (,) is biproduct in k, then: cont exr = Cont (join . inrF)
-}

  -- dup = Cont (jam . unjoin)
  dup :: forall a. Obj (Cont r k) a => Cont r k a (a, a)
  dup = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, a)) of
          (ObjR, ObjR) -> Cont (jamF . unjoin)
{-
If (,) is biproduct in k, then:
  cont dup
= Cont (. dup)
= Cont (\(f :: (a,a) `k` r) -> f . dup)
= Cont (\(f :: (a,a) `k` r) -> addBP (f . inl) (f . inr))
= Cont (\(f :: (a,a) `k` r) -> jamF (f . inl, f . inr))
= Cont (jamF . unjoin)
-}

instance (Cocartesian k, Obj k r) => Cocartesian (Cont r k) where
  -- inl = Cont (exl . unjoin)
  inl :: forall a b. (Obj (Cont r k) a, Obj (Cont r k) b) => Cont r k a (a, b)
  inl = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, b)) of
          (ObjR, ObjR) -> Cont (exl . unjoin)
{-
  cont inl
= Cont (. inl)
= Cont (\(f :: (a, b) `k` r) -> f . inl)
= Cont (\(f :: (a, b) `k` r) -> exl (f . inl, f . inr))
= Cont (\(f :: (a, b) `k` r) -> exl (unjoin f))
= Cont (exl . unjoin)
-}

  -- inr = Cont (exr . unjoin)
  inr :: forall a b. (Obj (Cont r k) a, Obj (Cont r k) b) => Cont r k b (a, b)
  inr = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, b)) of
          (ObjR, ObjR) -> Cont (exr . unjoin)
{-
  cont inr
= Cont (. inr)
= Cont (\(f :: (a, b) `k` r) -> f . inr)
= Cont (\(f :: (a, b) `k` r) -> exr (f . inl, f . inr))
= Cont (\(f :: (a, b) `k` r) -> exr (unjoin f))
= Cont (exr . unjoin)
-}

  -- jam = Cont (join . dup)
  jam :: forall a. Obj (Cont r k) a => Cont r k (a, a) a
  jam = case (monObj :: ObjR k (r, r), monObj :: ObjR k (a, a)) of
          (ObjR, ObjR) -> Cont (join . dup)
{-
  cont jam
= Cont (. jam)
= Cont (\(f :: a `k` r) -> f . jam)
= Cont (\(f :: a `k` r) -> f . (id ▽ id))
= Cont (\(f :: a `k` r) -> f ▽ f)
= Cont (\(f :: a `k` r) -> join (f, f)
= Cont (\(f :: a `k` r) -> join (dup f))
= Cont (join . dup)
-}

-- 論文では instance (Scalable k a) => Scalable (Cont r k) a だったけど、Category k も必要
instance (Category k, Obj k r, Scalable k a) => Scalable (Cont r k) a where
  -- 論文では scale s = Cont (scale s) だったけど型が合わない
  scale a = cont (scale a)
{-
  cont (scale a)
= Cont (. scale a)
-}

-- ------------------------------------------------------------------------

newtype Dual k a b = Dual (b `k` a)
-- 論文での定義はこれだけど onDot の結果が b -> a なので asDual が論文のように定義
-- 出来るためには後述の Dual' のような定義でないといけない。

unDual :: Dual k a b -> b `k` a
unDual (Dual f) = f

instance Category k => Category (Dual k) where
  type Obj (Dual k) a = Obj k a
  id = Dual id
  Dual g . Dual f = Dual (f . g)

instance Monoidal k => Monoidal (Dual k) where
  Dual f >< Dual g = Dual (f >< g)

  monObj :: forall a b. (Obj (Dual k) a, Obj (Dual k) b) => ObjR (Dual k) (a, b)
  monObj = case monObj :: ObjR k (a, b) of ObjR -> ObjR

-- 論文では Cartesian k を要求しているがそれは間違い
instance Cocartesian k => Cartesian (Dual k) where
  exl = Dual inl
  exr = Dual inr
  dup = Dual jam

-- 論文では Cocartesian k を要求しているがそれは間違い
instance Cartesian k => Cocartesian (Dual k) where
  inl = Dual exl
  inr = Dual exr
  jam = Dual dup

-- 論文では Scalable k => Scalable (Dual k) となっているがそれは間違い
instance Scalable k a => Scalable (Dual k) a where
  scale a = Dual (scale a)

instance (MonoidalI k h, Functor h, forall a. (Obj k a, Additive a) => Additive (h a)) => MonoidalI (Dual k) h where
  crossI = Dual . crossI . fmap unDual

  monObjI :: forall a. Obj (Dual k) a => ObjR (Dual k) (h a)
  monObjI = case monObjI :: ObjR k (h a) of ObjR -> ObjR

instance (CocartesianI k h, Functor h, forall a. (Obj k a, Additive a) => Additive (h a)) => CartesianI (Dual k) h where
  exI = fmap Dual inI
  replI = Dual jamI

instance (CartesianI k h, Functor h, forall a. (Obj k a, Additive a) => Additive (h a)) => CocartesianI (Dual k) h where
  inI = fmap Dual exI
  jamI = Dual replI

-- 前述のように onDot の型が違うので型検査を通らない
-- asDual :: (Obj k a, Obj k b, HasDot k s a , HasDot k s b) => Cont s k a b -> Dual k a b
-- asDual (Cont f) = Dual (onDot f)

-- ------------------------------------------------------------------------

newtype Dual' s (k :: * -> * -> *) a b = Dual' (b -> a)

unDual' :: Dual' s k a b -> (b -> a)
unDual' (Dual' f) = f

instance (Category k, Obj k s) => Category (Dual' s k) where
  type Obj (Dual' s k) a = (Obj k a, HasDot k s a)

  id = Dual' id
{-
  asDual' id
= asDual' (Cont id)
= Dual' (undot . id . dot)
= Dual' id
-}

  Dual' g . Dual' f = Dual' (f . g)
{-
  Dual' (undot . g . dot) . Dual' (undot . f . dot)
= asDual' (Cont g) . asDual' (Cont f)
= {- asDual' is expected to be a functor -}
  asDual' (Cont g . Cont f)
= asDual' (Cont (f . g))
= Dual' (undot . f . g . dot)
= Dual' (undot . f . id .  g . dot)
= Dual' (undot . f . (dot . undot) .  g . dot)
= Dual' ((undot . f . dot) . (undot . g . dot))
-}

instance (Cocartesian k, Obj k s) => Monoidal (Dual' s k) where
  Dual' f >< Dual' g = Dual' (f >< g)
{-
  Dual' (undot . f . dot) >< Dual' (undot . g . dot)
= asDual' (Cont f) >< asDual' (Cont g)
= {- asDual' is expected to preserve (><) -}
  asDual' (Cont f >< Cont g)
= asDual' (Cont (join . (f >< g) . unjoin))
= Dual' (undot . join . (f >< g) . unjoin . dot)
= Dual' (undot . join . (f >< g) . unjoin . (\(a,b) -> dot a ▽ dot b))
= Dual' (undot . join . (f >< g) . unjoin . join . (dot >< dot))
= Dual' (undot . join . (f >< g) . (dot >< dot))
= Dual' ((\(f,g) -> undot (f ▽ g)) . (f >< g) . (dot >< dot))
= Dual' ((\(f,g) -> (undot f, undot g)) . (f >< g) . (dot >< dot))
= Dual' ((undot >< undot) . (f >< g) . (dot >< dot))
= Dual' ((undot >< undot) . (f >< g) . (dot >< dot))
= Dual' ((undot . f . dot) >< (undot . g . dot))
-}

  monObj :: forall a b. (Obj (Dual' s k) a, Obj (Dual' s k) b) => ObjR (Dual' s k) (a, b)
  monObj = case monObj :: ObjR k (a, b) of ObjR -> ObjR

instance (Cartesian k, Cocartesian k, Obj k s, forall a. Obj k a => Additive (k a s)) => Cartesian (Dual' s k) where
{-
  exl :: forall a b. (Obj (Dual' s k) a, Obj (Dual' s k) b) => Dual' s k (a, b) a
  exl = case monObj :: ObjR k (a, b) of
          ObjR -> asDual' exl
-}
  exl = Dual' inlF
{-
  asDual' exl
= asDual' (Cont (join . inlF))
= Dual' (undot . join . inlF . dot)
= {- naturality of inlF -}
  Dual' (undot . join . (dot >< dot) . inlF)
= Dual' (undot . (\(a,b) -> join ((dot >< dot) (a,b))) . inlF)
= Dual' (undot . (\(a,b) -> join (dot a, dot b)) . inlF)
= Dual' (undot . (\(a,b) -> dot a ▽ dot b) . inlF)
= {- definition of dot (a,b) -}
  Dual' (undot . (\(a,b) -> dot (a,b)) . inlF)
= Dual' (undot . dot . inlF)
= Dual' (id . inlF)
= Dual' inlF
-}

{-
  exr :: forall a b. (Obj (Dual' s k) a, Obj (Dual' s k) b) => Dual' s k (a, b) b
  exr = case monObj :: ObjR k (a, b) of
          ObjR -> asDual' exr
-}
  exr = Dual' inrF
{-
Similarly, asDual' exr = Dual' inrF
-}

  dup :: forall a. (Obj (Dual' s k) a) => Dual' s k a (a, a)
  dup = Dual' jamF
{-
  asDual' dup
= asDual' (Cont (jamF . unjoin))
= Dual' (undot . jamF . unjoin . dot)
= {- naturality of jamF -}
  Dual' (jamF . (undot >< undot) . unjoin . dot)
= Dual' (jamF . (\h -> (undot >< undot) (unjoin h)) . dot)
= Dual' (jamF . (\h -> (undot >< undot) (h . inl, h . inr)) . dot)
= Dual' (jamF . (\h -> (undot (h . inl), undot (h . inr)) . dot)
= {- definition of undot h -}
  Dual' (jamF . (\h -> undot h) . dot)
= Dual' (jamF . undot . dot)
= Dual' (jamF . id)
= Dual' jamF
-}

instance (Cartesian k, Cocartesian k, Obj k s, forall a. Obj k a => Additive (k a s)) => Cocartesian (Dual' s k) where
{-
  inl :: forall a b. (Obj (Dual' s k) a, Obj (Dual' s k) b) => Dual' s k a (a, b)
  inl = case monObj :: ObjR k (a, b) of
          ObjR -> asDual' inl
-}
  inl = Dual' exl
{-
  asDual' inl
= asDual' Cont (exl . unjoin)
= Dual' (undot . exl . unjoin . dot)
= {- naturality of exl -}
  Dual' (exl . (undot >< undot) . unjoin . dot)
= Dual' (exl . (\h -> (undot >< undot) (unjoin h)) . dot)
= Dual' (exl . (\h -> (undot >< undot) (h . inl, h . inr)) . dot)
= Dual' (exl . (\h -> (undot (h . inl), undot (h . inr))) . dot)
= {- definition of undot h -}
  Dual' (exl . (\h -> undot h) . dot)
= Dual' (exl . undot . dot)
= Dual' (exl . id)
= Dual' exl
-}

{-
  inr :: forall a b. (Obj (Dual' s k) a, Obj (Dual' s k) b) => Dual' s k b (a, b)
  inr = case monObj :: ObjR k (a, b) of
          ObjR -> asDual' inr
-}
  inr = Dual' exr
{-
Similarly, asDual' inr = Dual' exr
-}

{-
  jam :: forall a. (Obj (Dual' s k) a) => Dual' s k (a, a) a
  jam = asDual' jam 
-}
  jam = Dual' dup
{-
  asDual' jam
= asDual' (Cont (join . dup))
= Dual' (undot . join . dup . dot)
= {- naturality of dup -}
  Dual' (undot . join . (dot >< dot) . dup)
= Dual' (undot . (\(a,b) -> join ((dot >< dot) (a,b))) . dup)
= Dual' (undot . (\(a,b) -> join (dot a, dot b)) . dup)
= Dual' (undot . (\(a,b) -> (dot a ▽ dot b)) . dup)
= {- definition of dot (a,b) -}
  Dual' (undot . (\(a,b) -> dot (a,b)) . dup)
= Dual' (undot . dot . dup)
= Dual' (id . dup)
= Dual' dup
-}

instance (Obj (Dual' s k) a, Scalable k a, Num a) => Scalable (Dual' s k) a where
  scale a = Dual' (scale a)
{-
  asDual' (scale a)
= asDual' (Cont (. scale a))
= Dual' (undot . (. scale a) . dot)
= {- これは成り立つ? -}
  Dual' (undot . dot . scale a)
= Dual' (id . scale a)
= Dual' (scale a)
-}

instance ( MonoidalI k h
         , Zip h
         , forall a. (Obj k a, Additive a) => Additive (h a)
         , forall a. (Obj k a, HasDot k s a) => HasDot k s (h a)
         , Obj k s
         ) => MonoidalI (Dual' s k) h where
  crossI = Dual' . crossI . fmap unDual'

  monObjI :: forall a. Obj (Dual' s k) a => ObjR (Dual' s k) (h a)
  monObjI = case monObjI :: ObjR k (h a) of ObjR -> ObjR

instance ( CocartesianI k h
         , Representable h
         , Eq (Rep h)
         , Zip h
         , Foldable h
         , forall a. (Obj k a, Additive a) => Additive (h a)
         , forall a. (Obj k a, HasDot k s a) => HasDot k s (h a)
         , Obj k s
         ) => CartesianI (Dual' s k) h where
  exI = fmap Dual' inIF
  replI = Dual' jamIF

instance ( CartesianI k h
         , Representable h
         , Zip h
         , Foldable h
         , forall a. (Obj k a, Additive a) => Additive (h a)
         , forall a. (Obj k a, HasDot k s a) => HasDot k s (h a)
         , Obj k s
         ) => CocartesianI (Dual' s k) h where
  inI = fmap Dual' exI
  jamI = Dual' replI

asDual' :: (Obj (Dual' s k) a, Obj (Dual' s k) b) => Cont s k a b -> Dual' s k a b
asDual' (Cont f) = Dual' (onDot f)

-- ------------------------------------------------------------------------

newtype Begin r k a b = Begin ((r `k` a) -> (r `k` b))

begin :: (Category k, Obj k a, Obj k b, Obj k r) => (a `k` b) -> Begin r k a b
begin f = Begin (f .)

instance (Category k, Obj k r) => Category (Begin r k) where
  type Obj (Begin r k) a = Obj k a
  id = Begin id
  Begin g . Begin f = Begin (g . f)

instance (Cartesian k, Obj k r) => Monoidal (Begin r k) where
  (><) :: forall a b c d. (Obj (Begin r k) a, Obj (Begin r k) b, Obj (Begin r k) c, Obj (Begin r k) d) =>
          Begin r k a b -> Begin r k c d -> Begin r k (a, c) (b, d)
  Begin f >< Begin g =
    case (monObj :: ObjR k (a, c), monObj :: ObjR k (b, d), monObj :: ObjR k (r, r)) of
      (ObjR, ObjR, ObjR) -> Begin (fork . (f >< g) . unfork)

  monObj :: forall a b. (Obj (Begin r k) a, Obj (Begin r k) b) => ObjR (Begin r k) (a, b)
  monObj = case monObj :: ObjR k (a, b) of ObjR -> ObjR

instance (Cartesian k, Obj k r) => Cartesian (Begin r k) where
  exl :: forall a b. (Obj (Begin r k) a, Obj (Begin r k) b) => Begin r k (a, b) a
  exl = case monObj :: ObjR k (a, b) of ObjR -> begin exl

  exr :: forall a b. (Obj (Begin r k) a, Obj (Begin r k) b) => Begin r k (a, b) b
  exr = case monObj :: ObjR k (a, b) of ObjR -> begin exr

  dup :: forall a. Obj (Begin r k) a => Begin r k a (a, a)
  dup = case monObj :: ObjR k (a, a) of ObjR -> begin dup

instance (Cartesian k, Cocartesian k, Obj k r) => Cocartesian (Begin r k) where
  inl :: forall a b. (Obj (Begin r k) a, Obj (Begin r k) b) => Begin r k a (a, b)
  inl = case monObj :: ObjR k (a, b) of ObjR -> begin inl

  inr :: forall a b. (Obj (Begin r k) a, Obj (Begin r k) b) => Begin r k b (a, b)
  inr = case monObj :: ObjR k (a, b) of ObjR -> begin inr

  jam :: forall a. Obj (Begin r k) a => Begin r k (a, a) a
  jam = case monObj :: ObjR k (a, a) of ObjR -> begin jam

instance (Category k, Obj k r, Scalable k a) => Scalable (Begin r k) a where
  scale s = begin (scale s)

-- ------------------------------------------------------------------------
