{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE MonoLocalBinds       #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE DataKinds            #-}
{-# LANGUAGE PolyKinds            #-}

module Html.Reify where

import Html.Type.Internal
import Html.Convert
import Html.CPP

import GHC.TypeLits
import Data.Proxy
import Data.Semigroup ((<>))

-- | Constraint synonym of html documents.
type Document a = Document' a

type Document' a = R (T (ToList a) a)

class R a where
  render :: a -> Converted

instance KnownSymbol a => R (T (prox :: [k]) (Proxy a)) where
  {-# INLINE render #-}
  render _ = mempty

instance R (T prox ()) where
  {-# INLINE render #-}
  render _ = mempty

instance {-# INCOHERENT #-}
  R (T '[] val) where
  {-# INLINE render #-}
  render _ = mempty

instance {-# INCOHERENT #-}
  ( Convert val
  ) => R (T '[ EmptySym ] val) where
  {-# INLINE render #-}
  render (T x) = convert x

instance {-# INCOHERENT #-}
  ( Convert val
  , Convert (Proxy s)
  ) => R (T '[s] val) where
  {-# INLINE render #-}
  render (T x) = convert (Proxy @ s) <> convert x

instance {-# INCOHERENT #-}
  ( R (T xs val)
  ) => R (T (NoTail xs) val) where
  {-# INLINE render #-}
  render (T t) = render (T t :: T xs val)

instance {-# INCOHERENT #-}
  ( R (T xs val)
  , Convert (Proxy x)
  ) => R (T ('FingerTree xs x) val) where
  {-# INLINE render #-}
  render (T t) = render (T t :: T xs val) <> convert (Proxy @ x)

instance
  ( R (T (Take (Length b) prox) b)
  , R (T (Drop (Length b) prox) c)
  ) => R (T prox ((a :@: b) c)) where
  {-# INLINE render #-}
  render (T ~(WithAttributes b c))
    = render (T b :: T (Take (Length b) prox) b)
   <> render (T c :: T (Drop (Length b) prox) c)

instance
  ( R (T (Take (Length a) prox) a)
  , R (T (Drop (Length a) prox) b)
  ) => R (T prox (a # b)) where
  {-# INLINE render #-}
  render (T ~(a :#: b))
    = render (T a :: T (Take (Length a) prox) a)
   <> render (T b :: T (Drop (Length a) prox) b)

instance
  ( R (T (ToList (a `f` b)) (a `f` b))
  , Convert (Proxy s)
  ) => R (T (s ': ss) [a `f` b]) where
  {-# INLINE render #-}
  render (T xs)
    = convert (Proxy @ s)
    <> foldMap (render . (T :: forall x. x -> T (ToList x) x)) xs
