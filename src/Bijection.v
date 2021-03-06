Set Implicit Arguments.

Require Import Coq.Lists.List.
Require Import Omega.

Section Defs.
  Variable A:Type.

  (** [MapsTo] is the last index of [x]. *)

  Inductive MapsTo (x:A) : nat -> list A -> Prop :=
  | maps_to_eq:
    forall l,
    MapsTo x (length l) (x::l)
  | maps_to_cons:
    forall l y n,
    x <> y ->
    MapsTo x n l ->
    MapsTo x n (y :: l).

  (** [IndexOf] assigns an element to an index with respect to a given list. *)

  Inductive IndexOf (x:A) : nat -> list A -> Prop :=
  | index_of_eq:
    forall l,
    IndexOf x (length l) (x :: l)
  | index_of_cons:
    forall y n l,
    IndexOf x n l ->
    IndexOf x n (y :: l).

  (** [First] obtains index [n] of the first occurence of [x] in [l]. *)

  Inductive First (x:A) : nat -> list A -> Prop :=
  | first_eq:
    forall l,
    ~ List.In x l ->
    First x (length l) (x::l)
  | first_cons:
    forall n l y,
    First x n l ->
    First x n (y::l).

  (** Checks if a number is an index of the given list,
      which is defined whenever there is an element [x] with an
      index of [n]. *)

  Inductive Index (n:nat) (l:list A) : Prop :=
  | index_def:
    forall x,
    IndexOf x n l ->
    Index n l.

  Lemma index_of_to_in:
    forall x n l,
    IndexOf x n l ->
    In x l.
  Proof.
    intros.
    induction l. {
      inversion H.
    }
    inversion H; subst.
    - auto using in_eq.
    - auto using in_cons.
  Qed.

  Lemma index_of_fun:
    forall l x n n',
    NoDup l ->
    IndexOf x n l ->
    IndexOf x n' l ->
    n' = n.
  Proof.
    intros.
    induction l. {
      inversion H0.
    }
    inversion H; subst; clear H.
    inversion H0; subst; clear H0.
    - inversion H1; subst; clear H1.
      + trivial.
      + contradiction H4; eauto using index_of_to_in.
    - inversion H1; subst; clear H1.
      + contradiction H4; eauto using index_of_to_in.
      + eauto.
  Qed.

  Lemma index_of_lt:
    forall x n l,
    IndexOf x n l ->
    n < length l.
  Proof.
    intros.
    induction l. {
      inversion H.
    }
    inversion H; subst.
    - auto.
    - simpl.
      assert (n < length l) by eauto.
      eauto.
  Qed.

  Lemma index_cons:
    forall n l x,
    Index n l ->
    Index n (x::l).
  Proof.
    intros.
    inversion H; subst; clear H.
    eauto using index_def, index_of_cons.
  Qed.

  Lemma lt_to_index:
    forall n l,
    n < length l ->
    Index n l.
  Proof.
    induction l; intros; simpl in *. {
      inversion H.
    }
    inversion H; subst; clear H.
    - eauto using index_def, index_of_eq.
    - auto using index_cons with *.
  Qed.

  Lemma index_lt:
    forall n l,
    Index n l ->
    n < length l.
  Proof.
    intros.
    inversion H.
    eauto using index_of_lt.
  Qed.

  Lemma index_iff_length:
    forall n l,
    Index n l <-> n < length l.
  Proof.
    split; auto using index_lt, lt_to_index.
  Qed.

  Lemma index_succ:
    forall n l,
    Index (S n) l ->
    Index n l.
  Proof.
    intros.
    rewrite index_iff_length in *.
    auto with *.
  Qed.

  Lemma in_to_index_of:
    forall l x,
    In x l ->
    exists n, n < length l /\ IndexOf x n l.
  Proof.
    induction l; intros. {
      inversion H.
    }
    destruct H.
    - subst.
      exists (length l).
      simpl.
      eauto using index_of_eq.
    - apply IHl in H.
      destruct H as (n, (?,?)).
      exists n.
      simpl.
      eauto using index_of_cons.
  Qed.

  Lemma index_of_bij:
    forall l x x' n,
    NoDup l ->
    IndexOf x n l ->
    IndexOf x' n l ->
    x' = x.
  Proof.
    intros.
    induction l. {
      inversion H0.
    }
    inversion H; clear H; subst.
    inversion H0; subst; clear H0.
    - inversion H1; subst; clear H1.
      + trivial.
      + assert (length l < length l). {
          eauto using index_of_lt.
        }
        omega.
    - inversion H1; subst; clear H1.
      + assert (length l < length l). {
          eauto using index_of_lt.
        }
        omega.
      + eauto.
  Qed.

  Lemma index_of_neq:
    forall l x y n n',
    NoDup l ->
    IndexOf x n l ->
    IndexOf y n' l ->
    n <> n' ->
    x <> y.
  Proof.
    intros.
    induction l. {
      inversion H0.
    }
    inversion H; clear H; subst.
    inversion H0; subst; clear H0.
    - inversion H1; subst; clear H1.
      + omega.
      + unfold not; intros; subst.
        contradiction H5.
        eauto using index_of_to_in.
    - inversion H1; subst; clear H1.
      + unfold not; intros; subst.
        contradiction H5.
        eauto using index_of_to_in.
      + eauto.
  Qed.

  Inductive Lt (l:list A) (x:A) (y:A) : Prop :=
  | lt_def:
    forall xn yn,
    IndexOf x xn l ->
    IndexOf y yn l ->
    xn < yn ->
    Lt l x y.

  Definition Gt (l:list A) (x:A) (y:A) : Prop := Lt l y x.

  Lemma lt_trans (l:list A) (N:NoDup l):
    forall x y z,
    Lt l x y ->
    Lt l y z ->
    Lt l x z.
  Proof.
    intros.
    inversion H; clear H.
    inversion H0; clear H0.
    rename yn0 into zn.
    assert (xn0 = yn) by
    eauto using index_of_fun; subst.
    apply lt_def with (xn:=xn) (yn:=zn); auto.
    omega.
  Qed.

  Lemma gt_trans (l:list A) (N:NoDup l):
    forall x y z,
    Gt l x y ->
    Gt l y z ->
    Gt l x z.
  Proof.
    unfold Gt; intros.
    eauto using lt_trans.
  Qed.

  Lemma lt_irrefl (l:list A) (N:NoDup l):
    forall x,
    ~ Lt l x x.
  Proof.
    intros.
    intuition.
    inversion H.
    assert (xn=yn) by eauto using index_of_fun.
    intuition.
  Qed.

  Lemma gt_irrefl (l:list A) (N:NoDup l):
    forall x,
    ~ Gt l x x.
  Proof.
    unfold Gt; intros.
    eauto using lt_irrefl.
  Qed.

  Lemma lt_neq (l:list A) (N:NoDup l):
    forall x y,
    Lt l x y ->
    x <> y.
  Proof.
    intros.
    inversion H; clear H.
    assert (xn <> yn) by omega.
    eauto using index_of_neq.
  Qed.

  Lemma gt_neq (l:list A) (N:NoDup l):
    forall x y,
    Gt l x y ->
    x <> y.
  Proof.
    unfold Gt; intros.
    apply lt_neq in H; auto.
  Qed.

  Lemma lt_absurd_nil:
    forall x y,
    ~ Lt nil x y.
  Proof.
    intuition.
    destruct H.
    inversion H.
  Qed.

  Lemma lt_cons:
    forall z l x y,
    Lt l x y ->
    Lt (z :: l) x y.
  Proof.
    intros.
    inversion H.
    eauto using lt_def, index_of_cons.
  Qed.

End Defs.


Section MapsTo.
  Variable A:Type.

  Lemma maps_to_inv_eq:
    forall (x:A) n vs,
    MapsTo x n (x :: vs) ->
    n = length vs.
  Proof.
    intros.
    inversion H; subst; auto.
    contradiction H3; trivial.
  Qed.

  Lemma maps_to_neq:
    forall (x:A) y vs n,
    x <> y ->
    MapsTo y n (x :: vs) ->
    MapsTo y n vs.
  Proof.
    intros.
    inversion H0.
    - subst; contradiction H; trivial.
    - assumption.
  Qed.

  Lemma maps_to_fun_2:
    forall vs (x:A) n n',
    MapsTo x n vs ->
    MapsTo x n' vs ->
    n' = n.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    inversion H; subst; clear H;
    inversion H0; subst; clear H0; auto.
    - contradiction H3; trivial.
    - contradiction H4; trivial.
    - eauto.
  Qed.

  Lemma maps_to_to_index_of:
    forall (x:A) nx vs,
    MapsTo x nx vs ->
    IndexOf x nx vs.
  Proof.
    intros.
    induction H. {
      auto using index_of_eq.
    }
    auto using index_of_cons.
  Qed.

  Lemma maps_to_lt:
    forall (x:A) n vs,
    MapsTo x n vs ->
    n < length vs.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    inversion H; subst. {
      auto.
    }
    apply IHvs in H4.
    simpl.
    auto.
  Qed.

  Lemma maps_to_absurd_length:
    forall (x:A) vs,
    ~ MapsTo x (length vs) vs.
  Proof.
    intros.
    unfold not; intros.
    apply maps_to_lt in H.
    apply Lt.lt_irrefl in H.
    assumption.
  Qed.

  Lemma index_of_absurd_length:
    forall (x:A) vs,
    ~ IndexOf x (length vs) vs.
  Proof.
    intuition.
    apply index_of_lt in H.
    omega.
  Qed.

  Lemma index_absurd_length:
    forall (vs:list A),
    ~ Index (length vs) vs.
  Proof.
    intuition.
    inversion H.
    apply index_of_absurd_length in H0.
    contradiction.
  Qed.

  Lemma maps_to_absurd_cons:
    forall (x:A) y n vs,
    MapsTo x n vs ->
    ~ (MapsTo y n (y :: vs)).
  Proof.
    intros.
    unfold not; intros.
    assert (n = length vs) by eauto using maps_to_inv_eq; subst.
    apply maps_to_absurd_length in H.
    contradiction.
  Qed.

  Lemma maps_to_inv_key:
    forall (x:A) y l,
    MapsTo y (length l) (x :: l) ->
    y = x.
  Proof.
    intros.
    inversion H; subst. {
      trivial.
    }
    apply maps_to_absurd_length in H4; contradiction.
  Qed.

  Lemma index_of_inv_key:
    forall (x:A) y l,
    IndexOf y (length l) (x :: l) ->
    y = x.
  Proof.
    intros.
    inversion H; subst. {
      trivial.
    }
    apply index_of_absurd_length in H2; contradiction.
  Qed.

  Lemma maps_to_fun_1:
    forall (x:A) y n vs,
    MapsTo x n vs ->
    MapsTo y n vs ->
    y = x.
  Proof.
    intros.
    induction H. {
      eauto using maps_to_inv_key.
    }
    inversion H0; subst. {
      apply maps_to_absurd_length in H1.
      contradiction.
    }
    auto.
  Qed.

  Lemma maps_to_to_in:
    forall (x:A) n vs,
    MapsTo x n vs ->
    List.In x vs.
  Proof.
    intros.
    induction H. {
      auto using List.in_eq.
    }
    auto using List.in_cons.
  Qed.

  Lemma index_eq:
    forall (x:A) vs,
    Index (length vs) (x::vs).
  Proof.
    intros.
    eauto using index_def, index_of_eq.
  Qed.

  Lemma maps_to_to_index:
    forall (x:A) n vs,
    MapsTo x n vs ->
    Index n vs.
  Proof.
    intros.
    eauto using index_def, maps_to_to_index_of.
  Qed.

End MapsTo.

Section IndexOf.
  Variable A:Type.

  Lemma index_of_tr:
    forall {A B} (a:list A) (b:list B) x n,
    length a = length b ->
    IndexOf x n a ->
    exists y, IndexOf y n b.
  Proof.
    induction a; intros. {
      inversion H0.
    }
    inversion H0; subst; clear H0. {
      destruct b. {
        simpl in H; inversion H.
      }
      simpl in *; inversion H.
      rewrite H1.
      eauto using index_of_eq.
    }
    destruct b. {
      simpl in *.
      inversion H.
    }
    simpl in *.
    inversion H.
    apply IHa with (b:=b0) in H3; auto.
    destruct H3 as (y, Hy).
    eauto using index_of_cons.
  Qed.

End IndexOf.

Section Index.
  Variable A:Type.

  Lemma index_tr:
    forall {A B} (a:list A) (b:list B) n,
    length a = length b ->
    Index n a ->
    Index n b.
  Proof.
    intros.
    inversion H0.
    apply index_of_tr with (b0:=b) in H1; auto.
    destruct H1 as (y, Hi).
    eauto using index_def.
  Qed.
End Index.

Section First.
  Variable A:Type.
  Variable eq_dec: forall (x y:A), {x = y} + {x <> y}.

  Lemma in_to_first:
    forall vs (x:A),
    List.In x vs ->
    exists n, First x n vs.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    destruct H. {
      subst.
      destruct (in_dec eq_dec x vs). {
        apply IHvs in i.
        destruct i as (n, Hf).
        eauto using first_cons.
      }
      eauto using first_eq.
    }
    apply IHvs in H.
    destruct H as (n, Hf).
    eauto using first_cons.
  Qed.

  Let first_to_in:
    forall vs (x:A) n,
    First x n vs ->
    List.In x vs.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    inversion H; subst; clear H. {
      auto using in_eq.
    }
    apply IHvs in H2.
    auto using in_cons.
  Qed.

  Let first_to_index_of:
    forall vs (x:A) n,
    First x n vs ->
    IndexOf x n vs.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    inversion H; subst; clear H. {
      auto using index_of_eq.
    }
    apply IHvs in H2.
    auto using index_of_cons.
  Qed.

  Lemma first_fun:
    forall vs (x:A) n n',
    First x n vs ->
    First x n' vs ->
    n = n'.
  Proof.
    induction vs; intros. {
      inversion H.
    }
    inversion H; subst; clear H. {
      inversion H0; subst; clear H0. {
        trivial.
      }
      contradiction H3; eauto using first_to_in.
    }
    inversion H0; subst; clear H0. {
      contradiction H2; eauto using first_to_in.
    }
    eauto.
  Qed.

  Lemma first_cons_fun:
    forall n n' (x:A) y vs,
    First x n vs ->
    First x n' (y :: vs) ->
    n' = n.
  Proof.
    intros.
    inversion H0; subst; clear H0. {
      contradiction H3.
      eauto using first_to_in.
    }
    eauto using first_fun.
  Qed.
End First.
