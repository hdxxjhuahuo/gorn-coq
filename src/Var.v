Require Coq.FSets.FMapFacts.
Require Coq.Arith.Compare_dec.

Require Aniceto.Map.

Require Import Coq.Structures.OrderedType.
Require Import Coq.Structures.OrderedTypeEx.
Require Import Coq.FSets.FMapAVL.
Require Import Coq.Arith.Peano_dec.
Require Import Omega.

Inductive var := varid : nat -> var.

Definition var_nat r := match r with | varid n => n end.

Definition var_first := varid 0.

Definition var_next m := varid (S (var_nat m)).

Module VAR <: UsualOrderedType.
  Definition t := var.
  Definition eq := @eq t.
  Definition lt x y := lt (var_nat x) (var_nat y).
  Definition eq_refl := @eq_refl t.
  Definition eq_sym := @eq_sym t.
  Definition eq_trans := @eq_trans t.
  Lemma lt_trans: forall x y z : t, lt x y -> lt y z -> lt x z.
  Proof.
    intros.
    unfold lt in *.
    destruct x, y, z.
    simpl in *.
    omega.
  Qed.

  Lemma lt_not_eq : forall x y : t, lt x y -> ~ eq x y.
  Proof.
    unfold lt in *.
    intros.
    destruct x, y.
    simpl in *.
    unfold not; intros.
    inversion H0.
    subst.
    apply Lt.lt_irrefl in H.
    inversion H.
  Qed.

  Import Coq.Arith.Compare_dec.
  Lemma compare:
    forall x y, Compare lt eq x y.
  Proof.
    intros.
    destruct x, y.
    destruct (Nat_as_OT.compare n n0);
    eauto using LT, GT.
    apply EQ.
    unfold Nat_as_OT.eq in *.
    subst.
    intuition.
  Qed.

  Lemma eq_dec : forall x y : t, {eq x y} + {~ eq x y}.
  Proof.
    intros.
    unfold eq.
    destruct x, y.
    destruct (eq_nat_dec n n0).
    - subst; eauto.
    - right.
      unfold not.
      intros.
      contradiction n1.
      inversion H; auto.
  Qed.
End VAR.


Module MV := FMapAVL.Make VAR.
Module MV_Facts := FMapFacts.Facts MV.
Module MV_Props := FMapFacts.Properties MV.

Import Aniceto.Map.

Module MV_Extra := MapUtil MV.
