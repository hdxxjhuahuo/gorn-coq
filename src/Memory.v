Set Implicit Arguments.

Require Import Coq.Lists.List.

Require Import Tid.
Require Import Lang.
Require Import Mid.
Require Import Shadow.
Require Import Node.
Require Import CG.
Require SJ_CG.

Module Locals.
Section Defs.
  Variable A:Type.

  Inductive op :=
  | COPY : node -> op
  | CONS : A -> node -> op
  | NEW : list A -> op.

  Definition task_local := list A.

  Definition local_memory := MN.t task_local.

  Inductive Reduces (m:local_memory): (node * op) -> local_memory -> Prop :=
  | reduces_copy:
    forall l n n',
    MN.MapsTo n l m ->
    ~ MN.In n' m ->
    Reduces m (n', COPY n) (MN.add n' l m)
  | reduces_cons:
    forall l x n n',
    MN.MapsTo n l m ->
    ~ MN.In n' m ->
    Reduces m (n', CONS x n) (MN.add n' (x::l) m)
  | reduces_new:
    forall l n,
    ~ MN.In n m ->
    Reduces m (n, NEW l) (MN.add n l m).

  Inductive MapsTo (n:node) (x:A) (ls:local_memory) : Prop :=
  | local_def:
    forall l,
    MN.MapsTo n l ls ->
    List.In x l ->
    MapsTo n x ls.


  Lemma maps_to_to_in:
    forall n x l,
    MapsTo n x l ->
    MN.In n l.
  Proof.
    intros.
    inversion H.
    eauto using MN_Extra.mapsto_to_in.
  Qed.
End Defs.
End Locals.

Section Defs.

  Import Locals.

  Inductive datum :=
  | d_task : tid -> datum
  | d_mem : mid -> datum
  | d_any : datum.


  Definition global_memory := access_history datum.

  Definition memory := (global_memory * (local_memory datum)) % type.

  Definition m_global (m:memory) := fst m.

  Definition m_local (m:memory) := snd m.

  Inductive op :=
  | CONTINUE: op
  | GLOBAL_ALLOC: mid -> datum -> op
  | GLOBAL_WRITE: mid -> datum -> op
  | GLOBAL_READ: mid -> op
  | FUTURE: tid -> list datum -> op
  | FORCE: tid -> datum -> op.

  Definition event := (tid * op) % type.


  Variable cg : computation_graph.

  Inductive Reduces : memory -> event -> memory -> Prop :=
  | reduces_g_read:
    forall g l d n n' (x:tid) y l' g' es nw vs,
    snd cg = C (n, n') :: es ->
    fst cg = x :: vs ->
    (* the reference y is in the locals of task x *)
    Locals.MapsTo n (d_mem y) l ->
    (* the contents of reference y is datum d *)
    Shadow.LastWrite y nw d g (vs,es) ->
    (* and the read is safe (race-free) *)
    HB cg nw n' ->
    (* add datum d to the locals of x *)
    Locals.Reduces l (n', CONS d n) l' ->
    (* update the shared memory to record the read *)
    Shadow.Reduces cg g (y, {| a_when := n'; a_what:=READ datum |}) g' ->
    Reduces (g, l) (x, GLOBAL_READ y) (g', l')

  | reduces_g_write:
    forall g (l:local_memory datum) (x:tid) (y:mid) d n n' g' es,
    (* a global write is a continue in the CG *)
    snd cg = C (n, n') :: es ->
    (* datum d being written is in the locals of task x *)
    Locals.MapsTo n d l ->
    (* the target reference is also in the locals of task x *)
    Locals.MapsTo n (d_mem y) l ->
    (* update the shared memory to record the write of datum d at reference y *)
    Shadow.Reduces cg g (y, {| a_when:=n'; a_what:=WRITE d|}) g' ->
    Reduces (g, l) (x, GLOBAL_WRITE y d) (g', l)

  | reduces_g_alloc:
    forall g l (x:tid) n n' d l' g' y es,
    (* a global alloc is a continue edge in the CG *)
    snd cg = C (n, n') :: es ->
    (* the datum being alloc'ed is a local *)
    Locals.MapsTo n d l ->
    (* update the shared memory with an alloc *)
    Shadow.Reduces cg g (y, {|a_when:=n;a_what:=ALLOC d|}) g' ->
    (* add reference y to the locals of task x *)
    Locals.Reduces l (n', CONS (d_mem y) n) l' ->
    Reduces (g, l) (x, GLOBAL_ALLOC y d) (g', l')

  | reduces_future:
    forall x nx nx' ny ds l g y l' l'' es,
    snd cg = F (nx, ny) :: C (nx, nx') :: es ->
    (* the locals of the new task are copied from the locals of the current task *)
    List.Forall (fun d => Locals.MapsTo nx d l) ds ->
    (* add task y to the locals of x *)
    Locals.Reduces l (nx', CONS (d_task y) nx) l' ->
    (* set the locals of y to be ds *)
    Locals.Reduces l' (ny, NEW ds) l'' ->
    Reduces (g, l) (x, FUTURE y ds) (g, l)

  | reduce_force:
    forall g l nx nx' ny d l' x y es,
    (* CG reduced with a join *)
    snd cg = J (ny,nx') :: C (nx,nx') :: es ->
    (* Datum d is in the locals of y *)
    Locals.MapsTo ny d l ->
    (* Add d to the locals of x *)
    Locals.Reduces l (nx', CONS d nx) l' ->
    Reduces (g, l) (x, FORCE y d) (g, l')

  | reduce_continue:
    forall g l x n n' l' es,
    snd cg = C (n, n') :: es ->
    Locals.Reduces l (n', COPY datum n) l' ->
    Reduces (g, l) (x, CONTINUE) (g, l').

  Inductive Knows (l:local_memory datum) : tid * tid -> Prop :=
  | knows_def:
    forall n x y,
    Node.MapsTo x n (fst cg) ->
    Locals.MapsTo n (d_task y) l ->
    Knows l (x, y).

End Defs.


Section SR.

  Definition op_to_cg (o:op) : CG.op :=
  match o with
  | CONTINUE => CG.CONTINUE
  | GLOBAL_ALLOC _ _ => CG.CONTINUE
  | GLOBAL_WRITE _ _ => CG.CONTINUE
  | GLOBAL_READ _ => CG.CONTINUE
  | FUTURE x _ => CG.FORK x
  | FORCE x _ => CG.JOIN x
  end.

  Definition event_to_cg (e:event) : CG.event :=
  let (x,o) := e in (x, op_to_cg o).

  Definition LocalToKnows (l:Locals.local_memory datum) cg sj :=
    forall p,
    Knows cg l p ->
    SJ_CG.Knows (fst cg) sj p.

  Let local_to_knows_continue_0:
    forall ls vs es x n l a an b sj k,
    LocalToKnows ls (vs, es) sj ->
    MapsTo x n vs ->
    MN.MapsTo n l ls ->
    ~ MN.In (fresh vs) ls ->
    MapsTo a an (x :: vs) ->
    Locals.MapsTo an (d_task b) (MN.add (fresh vs) l ls) ->
    SJ_CG.SJ (vs,es) k sj ->
    SJ_CG.Knows (x :: vs) (SJ_CG.Copy n :: sj) (a, b).
  Proof.
    intros.
    inversion H4; subst; clear H4.
    rename l0 into al.
    apply maps_to_inv in H3.
    destruct H3 as [(?,?)|(?,mt)]; subst. {
      rewrite MN_Facts.add_mapsto_iff in *.
      destruct H6 as [(_,?)|(N,_)]. {
        subst.
        assert (Hk: Knows (vs,es) ls (x, b))
        by eauto using knows_def, Locals.local_def.
        inversion H5.
        simpl in *.
        eauto using SJ_CG.knows_copy.
      }
      contradiction N; trivial.
    }
    rewrite MN_Facts.add_mapsto_iff in *.
    destruct H6 as [(?,?)|(?,mt')]. {
      subst.
      apply maps_to_absurd_fresh in mt.
      contradiction.
    }
    assert (Hk: Knows (vs,es) ls (a, b))
    by eauto using knows_def, Locals.local_def.
    apply H in Hk.
    simpl in *.
    inversion H5.
    simpl in *.
    eauto using SJ_CG.knows_neq.
  Qed.

  Let local_to_knows_continue:
    forall cg sj sj' cg' m m' a b x k,
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.CONTINUE) cg' ->
    Reduces cg' m (x, CONTINUE) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    rename H0 into CG_R.
    rename H1 into R.
    rename H2 into Hk.
    rename H3 into SJ_R.
    rename H4 into Hsj.
    inversion CG_R; subst; clear CG_R.
    simpl in *.
    apply maps_to_inv_eq in H4; subst.
    rename prev into nx.
    rename H2 into mt. (* MapsTo x nx vs *)
    clear H1. (* Live (vs, es) x *)
    inversion R; subst; clear R.
    simpl in *.
    inversion H1; subst; clear H1.
    rename es0 into es.
    inversion H3; subst; clear H3.
    rename l into ls; rename l0 into l.
    inversion SJ_R; subst; clear SJ_R.
    inversion Hk; subst; clear Hk.
    simpl in *.
    rename n0 into an.
    eauto.
  Qed.

  Let local_to_knows_alloc:
    forall cg sj sj' cg' m m' a b x k y d,
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.CONTINUE) cg' ->
    Reduces cg' m (x, GLOBAL_ALLOC y d) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    inversion H0; subst; clear H0.
    apply maps_to_inv_eq in H9; subst.
    rename prev into nx.
    inversion H1; subst; clear H1.
    simpl in *.
    inversion H9; subst; clear H9.
    rename es0 into es.
    inversion H14; subst; clear H14.
    inversion H3; subst; clear H3.
    inversion H13; subst; clear H13.
    rename l0 into ln.
    inversion H2; subst; clear H2.
    simpl in *.
    rename n0 into an.
    inversion H5; subst; clear H5.
    rename l0 into la.
    apply maps_to_inv in H3.
    rewrite MN_Facts.add_mapsto_iff in *.
    destruct H3 as [(?,?)|(?,mt)]. {
      subst.
      destruct H0 as [(_,?)|(N,_)]. {
        subst.
        destruct H1 as [Hx|?]. { inversion Hx. }
        inversion H4; subst.
        eauto using SJ_CG.knows_copy, knows_def, Locals.local_def.
      }
      contradiction N; trivial.
    }
    destruct H0 as [(?,?)|(?,mt')]. {
      subst.
      apply maps_to_absurd_fresh in mt.
      contradiction.
    }
    inversion H4; subst.
    eauto using SJ_CG.knows_neq, knows_def, Locals.local_def.
  Qed.

  Definition DomIncl (l:Locals.local_memory datum) (vs:list tid) :=
    forall n,
    MN.In n l ->
    Node n vs.

  Let local_to_knows_write:
    forall cg sj sj' cg' m m' a b x k y d,
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.CONTINUE) cg' ->
    Reduces cg' m (x, GLOBAL_WRITE y d) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    DomIncl (snd m) (fst cg) ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    rename H5 into Hdom.
    inversion H0; subst; clear H0.
    apply maps_to_inv_eq in H9; subst.
    rename prev into nx.
    inversion H1; subst; clear H1.
    simpl in *.
    inversion H9; subst; clear H9.
    rename es0 into es.
    inversion H14; subst; clear H14.
    inversion H3; subst; clear H3.
    inversion H2; subst; clear H2;
    simpl in *.
    rename n0 into an.
    apply maps_to_inv in H3.
    destruct H3 as [(?,?)|(?,mt)]. {
      subst.
      rename l0 into ly.
      apply Locals.maps_to_to_in in H5.
      apply Hdom in H5.
      apply node_absurd_fresh with (vs:=vs) in H5; auto; contradiction.
    }
    inversion H4; subst.
    eauto using SJ_CG.knows_neq, knows_def, Locals.local_def.
  Qed.

  Definition LastWriteCanJoin (g:access_history datum) cg sj :=
    forall m n x,
    LastWrite m n (d_task x) g cg ->
    SJ_CG.CanJoin n x sj.

  Let local_to_knows_read:
    forall cg sj sj' cg' m m' a b x k y k',
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.CONTINUE) cg' ->
    Reduces cg' m (x, GLOBAL_READ y) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    DomIncl (snd m) (fst cg) ->
    LastWriteCanJoin (fst m) cg sj ->
    SJ_CG.SJ cg' k' sj' ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    rename H5 into Hdom.
    rename H6 into Hwrite.
    rename H7 into Hsj'.
    inversion H1; subst; clear H1.
    destruct cg' as (vs', es').
    simpl in *.
    subst.
    inversion H0; subst; rename H0 into Hcg.
    apply maps_to_inv_eq in H17; subst.
    inversion H3; subst; clear H3.
    simpl in *.
    inversion H2; subst; clear H2.
    rename n0 into an.
    simpl in *.
    apply maps_to_inv in H3.
    inversion H13; subst; clear H13.
    inversion H15; subst; clear H15.
    rename l0 into ln.
    rename l1 into ly.
    inversion H5; subst; clear H5.
    rename l0 into la'.
    rewrite MN_Facts.add_mapsto_iff in *.
    destruct H3 as [(?,?)|(?,mt)]; subst. {
      subst.
      destruct H0 as [(_,Hx)|(N,_)]; subst. {
        destruct H1 as [?|Hi]. {
          subst.
          eauto using SJ_CG.knows_def, maps_to_eq, SJ_CG.hb_spec, SJ_CG.can_join_cons.
        }
        inversion H4.
        eauto using knows_def, Locals.local_def, SJ_CG.knows_copy.
      }
      contradiction N; trivial.
    }
    destruct H0 as [(?,?)|(?,mt')]. {
      subst.
      apply maps_to_absurd_fresh in mt; contradiction.
    }
    inversion H4; subst.
    eauto using SJ_CG.knows_neq, knows_def, Locals.local_def.
  Qed.

  Let local_to_knows_future:
    forall cg sj sj' cg' m m' a b x y k ds,
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.FORK y) cg' ->
    Reduces cg' m (x, FUTURE y ds) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    DomIncl (snd m) (fst cg) ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    rename H5 into Hdom.
    inversion H1; subst; clear H1.
    inversion H0; subst; rename H0 into Hcg.
    inversion H9; subst; clear H9.
    simpl in *.
    inversion H8; subst; clear H8.
    apply maps_to_inv_eq in H19; subst.
    apply maps_to_inv_eq in H16; subst.
    clear H18. (* MapsTo x nx vs *)
    inversion H3; subst; clear H3 H15.
    inversion H12; subst; clear H12.
    inversion H13; subst; clear H13.
    rename l0 into lx.
    inversion H2; subst; clear H2.
    simpl in *.
    apply maps_to_inv in H3.
    destruct H3 as [(?,?)|(?,mt)]. {
      subst.
      apply Locals.maps_to_to_in in H11.
      apply Hdom in H11.
      apply node_lt in H11.
      unfold NODE.lt, fresh in *.
      simpl in *.
      omega.
    }
    inversion H11; subst; clear H11.
    rename l0 into ln.
    apply maps_to_inv in mt.
    destruct mt as [(?,?)|(?,mt)]. {
      subst.
      apply MN_Extra.mapsto_to_in in H1.
      apply Hdom in H1.
      apply node_absurd_fresh with (vs:=vs) in H1; auto.
      contradiction.
    }
    eauto 6 using SJ_CG.knows_neq, knows_def, Locals.local_def.
  Qed.

  Let local_to_knows_force:
    forall cg sj sj' cg' m m' a b x k y d,
    LocalToKnows (snd m) cg sj ->
    CG.Reduces cg (x, CG.JOIN y) cg' ->
    Reduces cg' m (x, FORCE y d) m' ->
    Knows cg' (snd m') (a, b) ->
    SJ_CG.Reduces sj cg' sj' ->
    SJ_CG.SJ cg k sj ->
    SJ_CG.Knows (fst cg') sj' (a, b).
  Proof.
    intros.
    inversion H0; subst; clear H0.
    inversion H8; subst; clear H8.
    inversion H1; subst; clear H1.
    inversion H9; subst; clear H9.
    apply maps_to_inv_eq in H15; subst.
    simpl in *.
    inversion H3; subst; clear H3.
    assert (ty = y) by eauto using maps_to_fun_1; subst.
    clear H18 H11.
    apply maps_to_neq in H12; auto.
    rename nx0 into nx; rename ny0 into ny; rename es0 into es.
    inversion H17; subst; clear H17.
    apply maps_to_inv_eq in H10; subst.
    clear H10.
    rename l0 into lx.
    inversion H2; subst; clear H2.
    simpl in *.
    inversion H5; subst; clear H5.
    rename l0 into ln.
    rewrite MN_Facts.add_mapsto_iff in *.
    apply maps_to_inv in H3.
    destruct H3 as [(?,?)|(?,mt)]. {
      subst.
      destruct H0 as [(_,?)|(N,_)]. {
        subst.
        destruct H1 as [|Hi]. {
          subst.
          inversion H4; subst.
          eauto using SJ_CG.knows_append_right, knows_def, Locals.local_def.
        }
        inversion H4; subst.
        eauto using SJ_CG.knows_append_left, knows_def, Locals.local_def.
      }
      contradiction N; trivial.
    }
    destruct H0 as [(?,?)|(?, mt')]. {
      subst.
      apply maps_to_absurd_fresh in mt; contradiction.
    }
    eauto 6 using SJ_CG.knows_neq, knows_def, Locals.local_def.
  Qed.

  Lemma local_to_knows_reduces:
    forall cg k sj sj' cg' m m' e k',
    SJ_CG.SJ cg k sj ->
    LocalToKnows (snd m) cg sj ->
    SJ_CG.Events.Reduces k (event_to_cg e) k' ->
    CG.Reduces cg (event_to_cg e) cg' ->
    SJ_CG.SJ cg' k' sj' ->
    Reduces cg' m e m' ->
    SJ_CG.Reduces sj cg' sj' ->
    DomIncl (snd m) (fst cg) ->
    LastWriteCanJoin (fst m) cg sj ->
    SJ_CG.SJ cg' k' sj' ->
    LocalToKnows (snd m') cg' sj'.
  Proof.
    intros.
    unfold LocalToKnows.
    intros (a,b); intros.
    destruct e as (x, []); simpl in *.
    - eapply local_to_knows_continue; eauto.
    - eauto.
    - eauto.
    - eauto.
    - eauto.
    - eauto.
  Qed.
    

End SR.