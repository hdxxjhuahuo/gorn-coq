Require Aniceto.Graphs.Graph.
Require Aniceto.Graphs.DAG.
Require Trace.

Require Import Coq.Lists.List.
Require Import Coq.Relations.Relation_Definitions.
Require Import Coq.Lists.ListSet.
Require Import Aniceto.ListSet.
Require Import Aniceto.Graphs.Graph.
Require Import Omega.

Require Import Tid.
Require Import Mid.
Require Import Cid.
Require Import Var.
Require Import Dep.
Require Import Node.
(* ----- end of boiler-plate code ---- *)

Set Implicit Arguments.

Require Import Aniceto.Graphs.DAG.
Require Import Coq.Relations.Relation_Operators.
Require Import Coq.Structures.OrderedTypeEx.

Section Defs.

  Inductive op :=
  | INIT: op
  | FORK : tid -> op
  | JOIN : tid -> op
  | CONTINUE : op.

  Definition event := (tid * op) % type.
  Definition trace := list event.

  Inductive edge_type :=
  | E_FORK
  | E_JOIN
  | E_CONTINUE.

  Definition cg_edge := (edge_type * (node * node)) % type.
  Definition e_edge (e:cg_edge) := snd e.
  Definition e_t (e:cg_edge) := fst e.

End Defs.

Notation F e := (E_FORK, e).
Notation J e := (E_JOIN, e).
Notation C e := (E_CONTINUE, e).

Notation cg_edges es := (map e_edge es).

Section Edges.

  (**
    When creating a tee, the inter edge is the only thing
    that changes depending on the type of the node.
    *)


  Notation edge := (node * node) % type.

  Definition computation_graph := (list tid * list cg_edge) % type.

  Inductive Edge : list cg_edge -> edge_type -> (node * node) -> Prop :=
  | edge_def:
    forall es e,
    List.In e es ->
    Edge es (e_t e) (e_edge e).

  Inductive HB_Edge es e : Prop :=
  | hb_edge_def:
    forall t,
    Edge es t e ->
    HB_Edge es e.

  Lemma edge_eq:
    forall es t x y,
     List.In (t, (x,y)) es ->
     Edge es t (x, y).
  Proof.
    intros.
    remember (t,(x, y)) as e.
    assert (R:(x, y) = e_edge e) by (subst; auto).
    rewrite R.
    assert (R2:t = e_t e) by (subst; auto).
    rewrite R2.
    auto using edge_def.
  Qed.

  Lemma hb_edge_in:
    forall e es,
    List.In e es ->
    HB_Edge es (e_edge e).
  Proof.
    eauto using hb_edge_def, edge_def.
  Qed.

  Inductive CG: trace -> computation_graph -> Prop :=
  | cg_nil:
    CG nil (nil, nil)
  | cg_init:
    forall vs es x t,
    CG t (vs, es) ->
    ~ List.In x vs ->
    CG ((x, INIT)::t) (x::vs, es)
  | cg_fork:
    forall vs es y x nx nx' ny t,
    CG t (vs, es) ->
    ~ List.In y vs ->
    MapsTo x nx vs ->
    MapsTo y ny (y::x::vs) ->
    MapsTo x nx' (x::vs) ->
    CG ((x, FORK y)::t) (y::x::vs, F (nx,ny) :: C (nx, nx') :: es)
  | cg_join:
    forall vs es x y nx ny nx' t,
    CG t (vs, es) ->
    x <> y ->
    MapsTo x nx vs ->
    MapsTo x nx' (x::vs) ->
    MapsTo y ny (x::vs) ->
    CG ((x, JOIN y)::t) (x::vs, J (ny, nx') :: C (nx, nx') :: es)
  | cg_continue:
    forall vs (es:list cg_edge) x prev curr t,
    CG t (vs, es) ->
    MapsTo x prev vs ->
    MapsTo x curr (x::vs) ->
    CG ((x, CONTINUE)::t) (x::vs, C (prev, curr) :: es).

  Definition cg_nodes (cg:computation_graph) := fst cg.

  (** Every node of the CG is an index of the list of vertices. *)

  Definition EdgeToNode (cg:computation_graph) :=
    forall x y,
    HB_Edge (snd cg) (x, y) ->
    Node x (fst cg) /\ Node y (fst cg).


  Inductive SpawnPoint (x:tid) (n:node) : trace -> computation_graph -> Prop :=
  | spawn_point_init:
    forall vs es y t,
    ~ List.In y vs ->
    SpawnPoint x n t (vs, es) ->
    SpawnPoint x n ((y, INIT)::t) (y::vs, es)
  | spawn_point_eq:
    forall vs es n' n'' t y,
    SpawnPoint x n ((y, FORK x)::t) (x::vs, F (n', n'') :: C(n', n) :: es)
  | spawn_point_neq:
    forall vs es e y z t e',
    x <> y ->
    SpawnPoint x n t (vs, es) ->
    SpawnPoint x n ((z, FORK y)::t) (y::z::vs, (F e) :: (C e') :: es)
  | spawn_point_continue:
    forall vs es e y t,
    SpawnPoint x n t (vs, es) ->
    SpawnPoint x n ((y,CONTINUE)::t) (y::vs, (C e) :: es)
  | spawn_point_join:
    forall vs es e y z t e',
    SpawnPoint x n t (vs, es) ->
    SpawnPoint x n ((y,JOIN z)::t) (y::vs, (J e) :: (C e') :: es).
End Edges.

Section Props.

  Inductive Prec : (node * node) -> cg_edge -> Prop :=
  | prec_def:
    forall e,
    Prec (e_edge e) e.

  Variable es: list cg_edge.

  Let HB_Edge_alt e := List.Exists (Prec e) es.

  Definition HB := Reaches (HB_Edge es).

  Definition MHP x y : Prop := ~ HB x y /\ ~ HB y x.

  Definition Le x y := x = y \/ HB x y.

  Let in_edges_to_tees:
    forall e,
    List.In e (map e_edge es) ->
    exists x, List.In x es /\ Prec e x.
  Proof.
    intros.
    rewrite in_map_iff in *.
    destruct H as (x, (Hi, He)).
    exists x; split; auto.
    subst; eauto using prec_def.
  Qed.

  Let in_tees_to_edges:
    forall x e,
    List.In x es ->
    Prec e x ->
    List.In e (map e_edge es).
  Proof.
    intros.
    rewrite in_map_iff in *.
    inversion H0;
    subst;
    eauto.
  Qed.

  Lemma hb_trans:
    forall x y z,
    HB x y ->
    HB y z ->
    HB x z.
  Proof.
    intros.
    unfold HB in *.
    eauto using reaches_trans.
  Qed.

  (** Comparable with respect to the happens-before relation [n1 < n2 \/ n2 < n1] *)

  Inductive Comparable n1 n2 : Prop :=
  | comparable_left_right:
    HB n1 n2 ->
    Comparable n1 n2
  | comparable_right_left:
    HB n2 n1 ->
    Comparable n1 n2.

  Lemma comparable_symm:
    forall x y,
    Comparable x y ->
    Comparable y x.
  Proof.
    intros.
    inversion H; auto using comparable_left_right, comparable_right_left.
  Qed.

  Lemma comparable_to_not_mhp:
    forall x y,
    Comparable x y ->
    ~ MHP x y.
  Proof.
    intros.
    unfold not; intros.
    inversion H0.
    inversion H; contradiction.
  Qed.

  Inductive Relation x y : Prop :=
  | L_HB_R: HB x y -> Relation x y
  | R_HB_L: HB y x -> Relation x y
  | EQ: x = y -> Relation x y
  | PAR: MHP x y -> Relation x y.

  Require Aniceto.Graphs.FGraph.

  Lemma hb_dec:
    forall x y,
    { HB x y } + { ~ HB x y }.
  Proof.
    Admitted.
  (* TODO: prove this at the graph-level *)

End Props.

Section HB.

  Lemma hb_edge_spec:
    forall e es,
    HB_Edge es e <-> List.In e (map e_edge es).
  Proof.
    split; intros.
    - destruct H.
      inversion H; subst; clear H.
      simpl.
      auto using in_map.
    - rewrite in_map_iff in *.
      destruct H as (?,(?,?)); subst.
      simpl in *.
      eauto using hb_edge_in.
  Qed.

  Lemma node_lt_length_left:
    forall n1 n2 vs es,
    EdgeToNode (vs,es) ->
    List.In (n1, n2) (map e_edge es) ->
    NODE.lt n1 (fresh vs).
  Proof.
    intros.
    apply hb_edge_spec in H0.
    apply H in H0.
    destruct H0.
    auto using node_lt.
  Qed.

  Let walk2_edge_false:
    forall {A:Type} (x y:A) w,
    ~ Walk2 (fun _ => False) x y w.
  Proof.
    intuition.
    destruct H.
    destruct w.
    - eauto using starts_with_inv_nil.
    - eapply walk_to_edge; eauto using in_eq.
  Qed.

  Let reaches_edge_false:
    forall {A:Type} (x y:A),
    ~ Reaches (fun _ => False) x y.
  Proof.
    intuition.
    inversion H.
    apply walk2_edge_false in H0; auto.
  Qed.

  Lemma hb_to_fgraph:
    forall es x y,
    HB es x y ->
    Reaches (FGraph.Edge (map e_edge es)) x y.
  Proof.
    unfold HB.
    intros.
    apply reaches_impl with (E:=HB_Edge es); auto.
    intros.
    rewrite hb_edge_spec in *.
    simpl in *.
    auto.
  Qed.

  Lemma fgraph_to_hb:
    forall es x y,
    Reaches (FGraph.Edge (map e_edge es)) x y ->
    HB es x y.
  Proof.
    unfold  HB; intros.
    apply reaches_impl with (E:=FGraph.Edge (map e_edge es)); auto.
    intros.
    rewrite hb_edge_spec.
    auto.
  Qed.

  Lemma hb_fgraph_spec:
    forall es x y,
    HB es x y <->
    Reaches (FGraph.Edge (map e_edge es)) x y.
  Proof.
    split; eauto using hb_to_fgraph, fgraph_to_hb.
  Qed.

  Lemma hb_cons:
    forall e es x y,
    HB es x y ->
    HB (e :: es) x y.
  Proof.
    intros.
    rewrite hb_fgraph_spec in *.
    eauto using FGraph.reaches_cons.
  Qed.

  Lemma edge_to_hb:
    forall x y t es,
    HB ( (t, (x,y)) :: es) x y.
  Proof.
    intros.
    rewrite hb_fgraph_spec.
    simpl.
    unfold FGraph.Edge.
    auto using edge_to_reaches, in_eq.
  Qed.

End HB.

  Ltac simpl_red :=
  repeat match goal with
  | [ H: CG ((_, FORK _)::_) _   |- _ ] => inversion H; subst; clear H; simpl_node
  | [ H: CG ((_, JOIN _)::_) _   |- _ ] => inversion H; subst; clear H; simpl_node
  | [ H: CG ((_, CONTINUE)::_) _ |- _ ] => inversion H; subst; clear H; simpl_node
  | [ H: CG ((_, INIT)::_) _     |- _ ] => inversion H; subst; clear H; simpl_node
  end.

Section PropsEx.
(*
  Lemma make_edge_to_node:
    forall x,
    EdgeToNode (make_cg x).
  Proof.
    intros.
    unfold make_cg, EdgeToNode.
    intros.
    simpl in *.
    rewrite hb_edge_spec in H.
    simpl in *.
    contradiction.
  Qed.
*)
  Lemma edge_to_node_nil:
    EdgeToNode (nil, nil).
  Proof.
    unfold EdgeToNode; intros.
    simpl in *.
    rewrite hb_edge_spec in H.
    inversion H.
  Qed.

  Lemma edge_to_node_init:
    forall vs es x,
    EdgeToNode (vs, es) ->
    ~ List.In x vs ->
    EdgeToNode (x :: vs, es).
  Proof.
    unfold EdgeToNode; intros.
    assert (Hx: HB_Edge (snd (vs, es)) (x0, y)). {
      simpl in *; auto.
    }
    apply H in Hx.
    destruct Hx; simpl in *.
    split; auto using node_cons.
  Qed.

  Lemma edge_to_node_fork:
    forall vs es y x n,
    EdgeToNode (vs, es) ->
    ~ List.In y vs ->
    MapsTo x n vs ->
    EdgeToNode (y :: x :: vs, F (n, fresh (x :: vs)) :: C (n, fresh vs) :: es).
  Proof.
    unfold EdgeToNode; intros; simpl in *.
    apply hb_edge_spec in H2; simpl in *.
    destruct H2 as [Heq|[Heq|Hi]];
    try (inversion Heq; subst;
      split; eauto using maps_to_to_node, node_cons, node_eq).
    apply hb_edge_spec in Hi.
    apply H in Hi.
    destruct Hi; split; auto using node_cons.
  Qed.

  Lemma edge_to_node_join:
    forall vs es x y nx ny,
    EdgeToNode (vs, es) ->
    x <> y ->
    MapsTo x nx vs ->
    MapsTo y ny vs ->
    EdgeToNode (x :: vs, J (ny, fresh vs) :: C (nx, fresh vs) :: es).
  Proof.
    unfold EdgeToNode; intros.
    apply hb_edge_spec in H3; simpl in *.
    destruct H3 as [Heq|[Heq|Hi]];
    try (inversion Heq; subst;
      split; eauto using maps_to_to_node, node_cons, node_eq).
    apply hb_edge_spec in Hi.
    apply H in Hi.
    destruct Hi; split; auto using node_cons.
  Qed.

  Lemma edge_to_node_continue:
    forall x n vs es,
    EdgeToNode (vs, es) ->
    MapsTo x n vs ->
    EdgeToNode (x :: vs, C (n, fresh vs) :: es).
  Proof.
    unfold EdgeToNode; intros.
    apply hb_edge_spec in H1; simpl in *.
    destruct H1 as [Heq|Hi];
    try (inversion Heq; subst;
      split; eauto using maps_to_to_node, node_cons, node_eq).
    apply hb_edge_spec in Hi.
    apply H in Hi.
    destruct Hi; split; auto using node_cons.
  Qed.

  Let edge_to_node_in:
    forall vs es e a b,
    EdgeToNode (vs, es) ->
    List.In e es ->
    e_edge e = (a, b) ->
    Node a vs /\ Node b vs.
  Proof.
    intros.
    assert (He: HB_Edge es (e_edge e)) by auto using hb_edge_in.
    rewrite H1 in *.
    apply H in He.
    simpl in *.
    assumption.
  Qed.

  Let edge_to_node_in_fst:
    forall vs es e a b,
    EdgeToNode (vs, es) ->
    List.In e es ->
    e_edge e = (a, b) ->
    Node a vs.
  Proof.
    intros.
    assert (He : Node a vs /\ Node b vs) by eauto.
    destruct He; auto.
  Qed.

  Let edge_to_node_in_snd:
    forall vs es e a b,
    EdgeToNode (vs, es) ->
    List.In e es ->
    e_edge e = (a, b) ->
    Node b vs.
  Proof.
    intros.
    assert (He : Node a vs /\ Node b vs) by eauto.
    destruct He; auto.
  Qed.

  Lemma cg_to_edge_to_node:
    forall t cg,
    CG t cg ->
    EdgeToNode cg.
  Proof.
    induction t; intros. {
      inversion H; subst; clear H.
      auto using edge_to_node_nil.
    }
    inversion H; subst; clear H;
    apply IHt in H2; auto; simpl_node.
    - auto using edge_to_node_init.
    - auto using edge_to_node_fork.
    - eauto using edge_to_node_join.
    - auto using edge_to_node_continue.
  Qed.

  Lemma f_edge_to_hb_edge:
    forall es a b,
    FGraph.Edge (map e_edge es) (a, b) ->
    HB_Edge es (a, b).
  Proof.
    intros.
    rewrite hb_edge_spec.
    auto.
  Qed.

  Lemma edge_to_node_fresh_not_in:
    forall vs es,
    EdgeToNode (vs, es) ->
    ~ In (FGraph.Edge (map e_edge es)) (fresh vs).
  Proof.
    unfold not; intros.
    destruct H0 as ((v1,v2),(Hx,Hy)).
    assert (He: HB_Edge es (v1, v2)) by eauto using f_edge_to_hb_edge.
    apply H in He.
    destruct He as (Ha,Hb).
    simpl in *.
    destruct Hy; simpl in *; subst.
    - apply node_absurd_fresh in Ha; contradiction.
    - apply node_absurd_fresh in Hb; contradiction.
  Qed.

  Lemma in_edge_to_hb_edge:
    forall p es,
    List.In p (cg_edges es) ->
    HB_Edge es p.
  Proof.
    intros.
    apply in_map_iff in H.
    destruct H as (e, (?,He)); subst.
    auto using hb_edge_in.
  Qed.

  Lemma cg_edge_to_node_l:
    forall t vs es x y,
    CG t (vs, es) ->
    List.In (x, y) (map e_edge es) ->
    Node x vs.
  Proof.
    intros.
    assert (Hen: EdgeToNode (vs, es)) by eauto using cg_to_edge_to_node.
    assert (He: HB_Edge (snd (vs,es)) (x, y)). {
      auto using in_edge_to_hb_edge.
    }
    apply Hen in He.
    destruct He; auto.
  Qed.

  Lemma cg_edge_to_node_r:
    forall t vs es x y,
    CG t (vs, es) ->
    List.In (x, y) (map e_edge es) ->
    Node y vs.
  Proof.
    intros.
    assert (Hen: EdgeToNode (vs, es)) by eauto using cg_to_edge_to_node.
    assert (He: HB_Edge (snd (vs,es)) (x, y)). {
      auto using in_edge_to_hb_edge.
    }
    apply Hen in He.
    destruct He; auto.
  Qed.

  Lemma cg_hb_edge_to_node_r:
    forall t vs es x y,
    CG t (vs, es) ->
    HB_Edge es (x, y) ->
    Node y vs.
  Proof.
    intros.
    assert (Hen: EdgeToNode (vs, es)) by eauto using cg_to_edge_to_node.
    assert (He: HB_Edge (snd (vs,es)) (x, y)). {
      auto using in_edge_to_hb_edge.
    }
    apply Hen in He.
    destruct He; auto.
  Qed.

  Lemma edge_to_node_hb:
    forall vs es x y,
    EdgeToNode (vs, es) ->
    HB es x y ->
    Node x vs /\ Node y vs.
  Proof.
    intros.
    destruct H0.
    destruct w. {
      apply walk2_nil_inv in H0; contradiction.
    }
    destruct w. {
      apply walk2_inv_pair in H0.
      destruct H0.
      eauto.
    }
    apply walk2_inv in H0.
    destruct H0 as (z, (R, (Hx, Hy))).
    subst.
    apply H in Hx.
    destruct Hx as (Hx,_); split; auto; clear Hx.
    destruct Hy.
    destruct H1 as ((v3,v4), (Hx, Hy)).
    simpl in *; subst.
    eapply end_to_edge in Hx; eauto.
    apply H in Hx.
    destruct Hx; auto.
  Qed.

  Lemma edge_to_node_hb_fst:
    forall vs es x y,
    EdgeToNode (vs, es) ->
    HB es x y ->
    Node x vs.
  Proof.
    intros.
    eapply edge_to_node_hb in H0; eauto.
    destruct H0; auto.
  Qed.

  Lemma edge_to_node_hb_snd:
    forall vs es x y,
    EdgeToNode (vs, es) ->
    HB es x y ->
    Node y vs.
  Proof.
    intros.
    eapply edge_to_node_hb in H0; eauto.
    destruct H0; auto.
  Qed.

  Lemma hb_to_node_snd:
    forall t vs es x y,
    CG t (vs, es) ->
    HB es x y ->
    Node y vs.
  Proof.
    eauto using edge_to_node_hb_snd, cg_to_edge_to_node.
  Qed.

  Lemma hb_to_node_fst:
    forall t vs es x y,
    CG t (vs, es) ->
    HB es x y ->
    Node x vs.
  Proof.
    eauto using edge_to_node_hb_fst, cg_to_edge_to_node.
  Qed.

  Lemma hb_edge_cons:
    forall es e a b,
    HB_Edge es (a, b) ->
    HB_Edge (e :: es) (a, b).
  Proof.
    intros.
    rewrite hb_edge_spec in *.
    simpl in *.
    intuition.
  Qed.

  Lemma hb_impl_cons:
    forall es x y e,
    HB es x y ->
    HB (e::es) x y.
  Proof.
    intros.
    rewrite hb_fgraph_spec in *; simpl in *;
    eauto using FGraph.reaches_impl_cons.
  Qed.

  Lemma cg_fun:
    forall t cg cg',
    CG t cg ->
    CG t cg' ->
    cg' = cg.
  Proof.
    induction t; intros. {
      inversion H; inversion H0; subst; auto.
    }
    inversion H; subst; clear H; simpl_node;
    inversion H0; subst; clear H0;
    assert (Heq: (vs0, es0) = (vs,es)) by auto;
    inversion Heq; subst; clear Heq; simpl_node; trivial.
  Qed.

  Lemma hb_impl:
    forall a t cg cg',
    CG t cg ->
    CG (a::t) cg' -> 
    forall x y,
    HB (snd cg) x y ->
    HB (snd cg') x y.
  Proof.
    intros.
    destruct a as (?,[]);
    inversion H0; subst; clear H0; simpl_node; simpl in *;
    assert (cg = (vs,es)) by eauto using cg_fun; subst;
    eauto using hb_impl_cons.
  Qed.

  Lemma hb_impl_0:
    forall a t vs es vs' es',
    CG t (vs,es) ->
    CG (a::t) (vs', es') -> 
    forall x y,
    HB es x y ->
    HB es' x y.
  Proof.
    intros.
    assert (R1: es = snd (vs,es)) by auto.
    assert (R2: es' = snd (vs',es')) by auto.
    rewrite R1 in H1.
    rewrite R2.
    eauto using hb_impl.
  Qed.

  Lemma hb_absurd_node_l:
    forall vs es n,
    EdgeToNode (vs, es) ->
     ~ HB es (fresh vs) n.
  Proof.
    intros.
    unfold not; intros N.
    apply edge_to_node_hb_fst with (vs:=vs) in N; eauto; simpl_node.
  Qed.

  Lemma hb_absurd_node_r:
    forall vs es n,
    EdgeToNode (vs, es) ->
     ~ HB es n (fresh vs).
  Proof.
    intros.
    unfold not; intros N.
    apply edge_to_node_hb_snd with (vs:=vs) in N; eauto; simpl_node.
  Qed.

  Lemma hb_absurd_node_next_l:
    forall vs es n,
    EdgeToNode (vs, es) ->
     ~ HB es (node_next (fresh vs)) n.
  Proof.
    intros.
    unfold not; intros N.
    apply edge_to_node_hb_fst with (vs:=vs) in N; eauto; simpl_node.
  Qed.

  Lemma hb_absurd_node_next_r:
    forall vs es n,
    EdgeToNode (vs, es) ->
     ~ HB es n (node_next (fresh vs)).
  Proof.
    intros.
    unfold not; intros N.
    apply edge_to_node_hb_snd with (vs:=vs) in N; eauto; simpl_node.
  Qed.

End PropsEx.

  Ltac hb_simpl :=
  repeat match goal with
  | [ H1:HB ?es (fresh ?vs) _,H2: EdgeToNode (?vs, ?es) |- _] =>
    apply hb_absurd_node_l in H1; auto; contradiction
  | [ H1:HB ?es (node_next (fresh ?vs) )_,H2: EdgeToNode (?vs, ?es) |- _] =>
    apply hb_absurd_node_next_l in H1; auto; contradiction
  end.

Section DAG.
  Import Aniceto.Graphs.DAG.

  Let LtEdge e := NODE.lt (fst e) (snd e).
  Definition LtEdges es := List.Forall LtEdge es.
  Let Sup x (e:node*node) := NODE.lt (snd e) x.
  Definition HasSup cg := List.Forall (Sup (fresh (A:=tid) (fst cg))) (map e_edge (snd cg)).

  Let edge_to_lt:
    forall es x y,
    LtEdges es ->
    FGraph.Edge es (x, y) ->
    NODE.lt x y.
  Proof.
    intros.
    unfold FGraph.Edge in *.
    unfold LtEdges in *.
    rewrite List.Forall_forall in H.
    apply H in H0.
    auto.
  Qed.

  Let walk_2_to_lt:
    forall w x y es,
    LtEdges es ->
    Walk2 (FGraph.Edge es) x y w ->
    NODE.lt x y.
  Proof.
    induction w; intros. {
      apply walk2_nil_inv in H0.
      contradiction.
    }
    inversion H0; subst; clear H0.
    destruct a as (v1,v2).
    apply starts_with_eq in H1; subst.
    destruct w as [|(a,b)]. {
      apply ends_with_eq in H2.
      subst.
      assert (Hi: FGraph.Edge es (x,y)). {
        eapply walk_to_edge; eauto using List.in_eq.
      }
      eauto.
    }
    assert (Hlt: NODE.lt x v2). {
      assert (FGraph.Edge es (x, v2)) by (eapply walk_to_edge; eauto using List.in_eq).
      eauto.
    }
    inversion H3; subst; clear H3.
    apply linked_inv in H6; symmetry in H6; subst.
    apply ends_with_inv in H2.
    assert (NODE.lt a y) by eauto using walk2_def, starts_with_def.
    eauto using NODE.lt_trans.
  Qed.

  Let reaches_to_lt:
    forall x y es,
    LtEdges es ->
    Reaches (FGraph.Edge es) x y ->
    NODE.lt x y.
  Proof.
    intros.
    inversion H0.
    eauto.
  Qed.

  Lemma hb_to_lt:
    forall x y es,
    LtEdges (map e_edge es) ->
    HB es x y ->
    NODE.lt x y.
  Proof.
    intros.
    apply hb_to_fgraph in H0.
    eauto.
  Qed.

  Lemma lt_edges_to_dag:
    forall (es:list (node*node)),
    LtEdges es ->
    DAG (FGraph.Edge es).
  Proof.
    intros.
    unfold DAG.
    intros.
    unfold not; intros.
    apply reaches_to_lt in H0; auto.
    unfold NODE.lt in *.
    omega.
  Qed.

  Let maps_to_lt_edge_cons:
    forall {A:Type} (x:A) n vs,
    MapsTo x n vs ->
    LtEdge (n, fresh (x :: vs)).
  Proof.
    intros.
    apply maps_to_lt in H.
    unfold NODE.lt, fresh in *.
    unfold LtEdge; simpl in *.
    omega.
  Qed.

  Let maps_to_lt_edge:
    forall {A:Type} (x:A) n vs,
    MapsTo x n vs ->
    LtEdge (n, fresh vs).
  Proof.
    intros.
    apply maps_to_lt in H.
    unfold NODE.lt, fresh in *.
    unfold LtEdge; simpl in *.
    omega.
  Qed.

  Lemma cg_to_lt_edges:
    forall t (cg:computation_graph),
    CG t cg ->
    LtEdges (map e_edge (snd cg)).
  Proof.
    induction t; intros. {
      inversion H; subst; simpl.
      unfold LtEdges.
      auto using List.Forall_nil.
    }
    inversion H; subst; clear H; simpl_node; simpl in *; auto;
    apply IHt in H2; simpl in *; unfold LtEdges in *; auto;
    eauto using List.Forall_cons.
  Qed.

  Lemma cg_to_lt_edges_0:
    forall t vs es,
    CG t (vs, es) ->
    LtEdges (map e_edge es).
  Proof.
    intros.
    assert (R: es = snd (vs,es)) by auto; rewrite R.
    eauto using cg_to_lt_edges.
  Qed.

  Lemma hb_irrefl:
    forall x es,
    LtEdges (map e_edge es) ->
    ~ HB es x x.
  Proof.
    intros.
    apply lt_edges_to_dag in H.
    unfold DAG in *.
    unfold not; intros.
    apply hb_fgraph_spec in H0.
    simpl in *.
    apply H in H0.
    contradiction.
  Qed.

  Lemma cg_irrefl:
    forall t cg,
    CG t cg ->
    forall x, ~ HB (snd cg) x x.
  Proof.
    intros.
    apply cg_to_lt_edges in H.
    auto using hb_irrefl.
  Qed.

  Lemma cg_irrefl_0:
    forall t vs es,
    CG t (vs, es) ->
    forall x, ~ HB es x x.
  Proof.
    intros.
    eapply cg_irrefl in H; simpl; eauto.
  Qed.

  Let sub_fresh_cons_lhs:
    forall {A:Type} (x:A) vs n,
    Sup (fresh (x :: vs)) (n, fresh vs).
  Proof.
    intros.
    unfold Sup.
    simpl.
    unfold NODE.lt, fresh; simpl; omega.
  Qed.

  Let sub_fresh_cons_cons:
    forall {A:Type} (x y:A) vs n,
    MapsTo x n vs ->
    Sup (fresh (y :: x :: vs)) (n, fresh vs).
  Proof.
    intros.
    unfold Sup.
    simpl.
    unfold NODE.lt, fresh; simpl; omega.
  Qed.

  Let lt_fresh_cons:
    forall {A:Type} (x:A) vs,
    NODE.lt (fresh vs) (fresh (x::vs)).
  Proof.
    intros.
    unfold NODE.lt, fresh; simpl; auto.
  Qed.

  Let sub_fresh_cons:
    forall vs x (t:tid),
    Sup (fresh vs) x ->
    Sup (fresh (t :: vs)) x.
  Proof.
    unfold Sup; intros.
    simpl in *.
    assert (NODE.lt (fresh vs) (fresh (t::vs))). {
      unfold fresh in *; simpl in *.
      auto with *.
    }
    eauto using NODE.lt_trans.
  Qed.

  Lemma cg_to_has_sup:
    forall t cg,
    CG t cg ->
    HasSup cg.
  Proof.
    induction t; intros. {
      inversion H; subst; clear H.
      unfold HasSup; simpl; intros; auto using List.Forall_nil.
    }
    inversion H; subst; clear H;
    apply IHt in H2; clear IHt;
    unfold HasSup in *; simpl in *; simpl_node;
    rewrite List.Forall_forall in *; intros.
    - auto.
    - inversion H; subst; clear H. {
        unfold Sup; simpl.
        eauto using NODE.lt_trans.
      }
      inversion H0; subst; clear H0. {
        unfold Sup; simpl.
        eauto using NODE.lt_trans.
      }
      auto.
    - inversion H; subst; clear H. {
        unfold Sup; simpl.
        eauto using NODE.lt_trans.
      }
      inversion H0; subst; clear H0. {
        unfold Sup; simpl.
        eauto using NODE.lt_trans.
      }
      auto.
    - inversion H; subst; clear H. {
        unfold Sup; simpl.
        eauto using NODE.lt_trans.
      }
      auto.
  Qed.

  Let walk2_to_hb:
    forall es a b w n1 n2 t,
    Walk2 (FGraph.Edge ((n1, n2) :: map e_edge es)) a b w ->
    HB ((t, (n1,n2)) :: es) a b.
  Proof.
    intros.
    apply fgraph_to_hb.
    simpl.
    eauto using reaches_def.
  Qed.

  Notation in_edge_dec := (in_dec (Pair.pair_eq_dec node_eq_dec)).

  Lemma edge_to_node_cons_node:
    forall x vs es,
    EdgeToNode (vs, es) ->
    EdgeToNode (x::vs, es).
  Proof.
    intros.
    unfold EdgeToNode.
    intros a b; intros.
    simpl.
    assert (He: HB_Edge es (a,b)). {
      rewrite hb_edge_spec in *.
      simpl in *.
      assumption.
    }
    apply H in He.
    destruct He.
    simpl in *.
    auto using node_cons.
  Qed.

  Lemma hb_edge_eq:
    forall es x y t,
    HB_Edge ((t,(x, y)) :: es) (x, y).
  Proof.
    intros.
    rewrite hb_edge_spec in *.
    simpl in *.
    auto.
  Qed.

  Lemma hb_edge_to_hb:
    forall es x y,
    HB_Edge es (x,y) ->
    HB es x y.
  Proof.
    intros.
    rewrite hb_fgraph_spec.
    rewrite hb_edge_spec in H.
    eauto using edge_to_reaches.
  Qed.

  Lemma edge_to_node_inv_cons_edge:
    forall vs es x y t,
    EdgeToNode (vs, (t, (x,y))::es) ->
    EdgeToNode (vs, es) /\ Node x vs /\ Node y vs.
  Proof.
    intros.
    split;
    try unfold EdgeToNode; simpl; intros;
    eauto using hb_edge_eq, hb_edge_cons, hb_edge_to_hb, edge_to_node_hb_snd, edge_to_node_hb_fst.
  Qed.

  Lemma edge_to_node_cons_edge:
    forall vs es x y t,
    EdgeToNode (vs, es) ->
    Node x vs ->
    Node y vs ->
    EdgeToNode (vs, (t,(x,y))::es).
  Proof.
    intros.
    unfold EdgeToNode; intros a b; intros.
    simpl.
    rewrite hb_edge_spec in *.
    simpl in *.
    destruct H2.
    - inversion H2; subst; auto.
    - apply H.
      rewrite hb_edge_spec in *.
      auto.
  Qed.

  Lemma lt_edges_inv_cons_edge:
    forall es x y t,
    LtEdges (map e_edge ((t,(x,y))::es)) ->
    LtEdges (map e_edge es) /\ LtEdge (x,y).
  Proof.
    intros.
    unfold LtEdges in *.
    inversion H; subst.
    auto.
  Qed.

  Lemma lt_edges_cons_edge:
    forall es x y t,
    LtEdges (map e_edge es) ->
    LtEdge (x,y) ->
    LtEdges (map e_edge ((t,(x,y))::es)).
  Proof.
    intros.
    unfold LtEdges in *.
    apply List.Forall_cons; auto.
  Qed.

  Let hb_inv_cons_c_0:
    forall a b vs x n es t,
    EdgeToNode (x::vs, (t, (n,fresh vs)) :: es) ->
    LtEdges (map e_edge ((t, (n,fresh vs)) :: es)) ->
    HB ((t,(n,fresh vs)) :: es) a b ->
    HB es a b \/ b = fresh vs.
  Proof.
    intros.
    rewrite hb_fgraph_spec in *.
    simpl in *.
    destruct H1 as (w, Hw).
    (* -- *)
    destruct (in_edge_dec (n, fresh vs) w). {
      apply in_split in i.
      destruct i as (w1, (w2, R)); subst.
      destruct w1. {
        simpl in *.
        destruct w2. {
          apply walk2_inv_eq_snd in Hw.
          subst.
          auto.
        }
        apply walk2_inv in Hw.
        destruct Hw as (c, (R, (He, Hw))).
        inversion R; subst; clear R.
        eapply walk2_to_hb with (t:=t) in Hw; auto.
        assert (Hb: Node b (x::vs)) by eauto using edge_to_node_hb_snd.
        apply node_inv in Hb.
        destruct Hb as [?|Hb]; auto.
        apply node_lt in Hb.
        apply hb_to_lt in Hw; auto.
        unfold NODE.lt in *; simpl in *; omega.
      }
      apply walk2_split_app in Hw.
      destruct Hw as (_,Hw).
      destruct w2. {
        apply walk2_inv_eq_snd in Hw.
        subst.
        auto.
      }
      apply walk2_inv in Hw.
      destruct Hw as (c, (R, (He, Hw))).
      inversion R; subst; clear R.
      apply walk2_to_hb with (t:=t) in Hw; auto.
      assert (Hb: Node b (x::vs)) by eauto using edge_to_node_hb_snd.
      apply node_inv in Hb.
      destruct Hb as [?|Hb]; auto.
      apply node_lt in Hb.
      apply hb_to_lt in Hw; auto.
      unfold NODE.lt in *; simpl in *; omega.
    }
    left; 
    eauto using FGraph.walk2_inv_not_in_walk, reaches_def.
  Qed.

  Lemma hb_inv_cons_c:
    forall a b vs x n es t k,
    CG t (x::vs, (k, (n,fresh vs)) :: es) ->
    HB ((k,(n,fresh vs)) :: es) a b ->
    HB es a b \/ b = fresh vs.
  Proof.
    intros.
    eapply hb_inv_cons_c_0; eauto using cg_to_edge_to_node, cg_to_lt_edges_0.
  Qed.

  Lemma hb_inv_cons:
    forall x y n1 n2 t es,
    DAG (FGraph.Edge (cg_edges ((t, (n1, n2))::es))) ->
    HB ((t, (n1, n2))::es) x y ->
    HB es x y \/
    (n2 = y /\ (n1 = x \/ HB es x n1)) \/
    (n2 <> y /\ HB es n2 y) \/
    (HB es x n1 /\ HB es n2 y).
  Proof.
    intros.
    repeat rewrite hb_fgraph_spec in *.
    simpl in H0.
    inversion H0; clear H0.
    destruct (List.in_dec (Pair.pair_eq_dec node_eq_dec) (n1,n2) w). {
      right.
      eauto using Graphs.DAG.reaches_inv_cons, node_eq_dec.
    }
    apply FGraph.walk2_inv_not_in_walk in H1; eauto using reaches_def.
  Qed.

  Lemma cg_to_dag:
    forall t cg,
    CG t cg ->
    DAG (FGraph.Edge (cg_edges (snd cg))).
  Proof.
    eauto using cg_to_lt_edges, lt_edges_to_dag.
  Qed.

  Lemma cg_hb_absurd_node_l:
    forall t vs es n,
    CG t (vs, es) ->
    ~ HB es (fresh vs) n.
  Proof.
    eauto using cg_to_edge_to_node, hb_absurd_node_l.
  Qed.

  Lemma cg_hb_absurd_node_r:
    forall t vs es n,
    CG t (vs, es) ->
    ~ HB es n (fresh vs).
  Proof.
    eauto using cg_to_edge_to_node, hb_absurd_node_r.
  Qed.

  Lemma cg_hb_absurd_node_next_l:
    forall vs es n t,
    CG t (vs, es) ->
     ~ HB es (node_next (fresh vs)) n.
  Proof.
    eauto using cg_to_edge_to_node, hb_absurd_node_next_l.
  Qed.

  Lemma cg_hb_absurd_node_next_r:
    forall vs es n t,
    CG t (vs, es) ->
     ~ HB es n (node_next (fresh vs)).
  Proof.
    eauto using cg_to_edge_to_node, hb_absurd_node_next_r.
  Qed.

  Lemma hb_inv_cons_fork:
    forall x y a b t es n vs,
    CG ((x, FORK y)::t) (y::x::vs, F (n, fresh (x::vs)) :: C (n, fresh vs):: es) ->
    HB (F (n, fresh (x::vs)) :: C (n, fresh vs)::es) a b ->
    HB es a b \/
    (fresh vs = b /\ n = a) \/
    (fresh vs = b /\ HB es a n) \/
    (fresh (x :: vs) = b /\ n = a) \/
    (fresh (x :: vs) = b /\ HB es a n) \/
    (fresh (x :: vs) = b /\ fresh vs = n /\ HB es a n) \/
    (fresh (x :: vs) <> b /\ fresh vs = b /\ n = fresh (x :: vs)).
  Proof.
    intros.
    inversion H; subst; simpl_node.
    apply cg_to_dag in H; simpl in *.
    rename H into Hy.
    assert (Hx:DAG (FGraph.Edge ((n, fresh vs) :: cg_edges es))). {
      eauto using f_dag_inv_cons.
    }
    apply hb_inv_cons in H0; auto.
    destruct H0 as [Hc|[(?,[?|Hc])|[(?,Hc)|(Ha,Hc)]]].
    - apply hb_inv_cons in Hc; auto.
      destruct Hc as [?|[(?,[?|?])|[(_,N)|(_,N)]]]; auto;
      try (eapply cg_hb_absurd_node_l in N; eauto; contradiction).
    - intuition.
    - apply hb_inv_cons in Hc; auto.
      destruct Hc as [?|[(?,[?|Hc])|[(_,N)|(_,N)]]];
      try (eapply cg_hb_absurd_node_l in N; eauto; contradiction);
      intuition.
    - apply hb_inv_cons in Hc; auto.
      destruct Hc as [N|[(?,[?|N])|[(?,N)|(_,N)]]].
      + rewrite fresh_cons_rw_next in *.
        eapply cg_hb_absurd_node_next_l in N; eauto; contradiction.
      + intuition.
      + rewrite fresh_cons_rw_next in *.
        eapply cg_hb_absurd_node_next_l in N; eauto; contradiction.
      + eapply cg_hb_absurd_node_l in N; eauto; contradiction.
      + eapply cg_hb_absurd_node_l in N; eauto; contradiction.
    - apply hb_inv_cons in Hc; auto.
      destruct Hc as [N|[(?,[?|Hc])|[(?,Hc)|(Hb,Hc)]]].
      + rewrite fresh_cons_rw_next in *.
        eapply cg_hb_absurd_node_next_l in N; eauto; contradiction.
      + apply hb_inv_cons in Ha; auto.
        destruct Ha as [N|[(?,[?|N])|[(?,N)|(Hb,N)]]].
        * subst.
          rewrite fresh_cons_rw_next in *.
          eapply cg_hb_absurd_node_next_r in N; eauto; contradiction.
        * subst.
          simpl_node.
        * subst.
          eapply cg_hb_absurd_node_r in N; eauto; contradiction.
        * subst.
          eapply cg_hb_absurd_node_l in N; eauto; contradiction.
        * eapply cg_hb_absurd_node_l in N; eauto; contradiction.
      + rewrite fresh_cons_rw_next in *.
        eapply cg_hb_absurd_node_next_l in Hc; eauto; contradiction.
      + eapply cg_hb_absurd_node_l in Hc; eauto; contradiction.
      + eapply cg_hb_absurd_node_l in Hc; eauto; contradiction.
  Qed.

  Lemma hb_inv_cons_join:
    forall x y a b t es vs nx ny,
    CG ((x, JOIN y)::t) (x::vs, J (ny, fresh vs) :: C (nx, fresh vs):: es) ->
    HB (J (ny, fresh vs) :: C (nx, fresh vs)::es) a b ->
    HB es a b \/
    (fresh vs = b /\ nx = a) \/
    (fresh vs = b /\ HB es a nx) \/
    (fresh vs = b /\ ny = a) \/
    (fresh vs = b /\ HB es a ny).
  Proof.
    intros.
    inversion H; subst; simpl_node.
    apply cg_to_dag in H; simpl in *.
    rename H into Hdag.
    assert (Hx:DAG (FGraph.Edge ((nx, fresh vs) :: cg_edges es))). {
      eauto using f_dag_inv_cons.
    }
    apply hb_inv_cons in H0; auto. (* HB *)
    destruct H0 as [Hc|[(?,[?|Hc])|[(?,Hc)|(Ha,Hc)]]].
    - apply hb_inv_cons in Hc; auto. (* HB *)
      destruct Hc as [?|[(?,[?|Hc])|[(?,N)|(Ha,N)]]]; auto;
      eapply cg_hb_absurd_node_l in N; eauto; contradiction.
    - intuition.
    - apply hb_inv_cons in Hc; auto. (* HB *)
      destruct Hc as [?|[(?,[?|Hc])|[(?,N)|(Ha,N)]]]; auto.
      + intuition.
      + eapply cg_hb_absurd_node_l in N; eauto; contradiction.
    - apply hb_inv_cons in Hc; auto. (* HB *)
      destruct Hc as [N|[(?,[?|N])|[(?,N)|(Ha,N)]]]; auto;
      try (eapply cg_hb_absurd_node_l in N; eauto; contradiction).
      + contradiction.
    - apply hb_inv_cons in Hc; auto. (* HB *)
      destruct Hc as [N|[(?,[?|N])|[(?,N)|(Hb,N)]]]; auto;
      try (eapply cg_hb_absurd_node_l in N; eauto; contradiction).
      apply hb_inv_cons in Ha; auto. (* HB *)
      destruct Ha as [N|[(?,[?|N])|[(?,N)|(Hb,N)]]]; auto;
      try (eapply cg_hb_absurd_node_l in N; eauto; contradiction).
      intuition.
  Qed.

  Lemma hb_inv_cons_continue:
    forall x a b t es vs n,
    CG ((x, CONTINUE)::t) (x::vs, C (n, fresh vs):: es) ->
    HB (C (n, fresh vs)::es) a b ->
    HB es a b \/
    (fresh vs = b /\ n = a) \/
    (fresh vs = b /\ HB es a n).
  Proof.
    intros.
    inversion H; subst; simpl_node.
    apply cg_to_dag in H; simpl in *.
    rename H into Hy.
    apply hb_inv_cons in H0; auto.
    destruct H0 as [Hc|[(?,[?|Hc])|[(?,N)|(Ha,N)]]];
    auto; eapply cg_hb_absurd_node_l in N; eauto; contradiction.
  Qed.

  Lemma hb_inv_continue_1:
    forall a vs x n es t,
    CG ((x,CONTINUE)::t) (x::vs, (C (n,fresh vs)) :: es) ->
    HB (C (n,fresh vs) :: es) a (fresh vs) ->
    a = n \/ HB es a n.
  Proof.
    intros.
    assert (Hx:=H).
    apply cg_to_dag in H.
    apply hb_inv_cons in H0; auto.
    destruct H0 as [?|[(?,[?|?])|[(N,_)|(?,_)]]]; auto.
    - apply edge_to_node_hb_snd with (vs:=vs) in H0.
      + simpl_node.
      + inversion Hx; subst; clear Hx.
        eauto using cg_to_edge_to_node.
    - contradiction.
  Qed.

  Lemma hb_absurd_cons_c:
    forall n (vs:list tid) es b t x,
    CG ((x,CONTINUE)::t) (x::vs, C (n, fresh vs) :: es) ->
    ~ HB (C (n, fresh vs) :: es) (fresh vs) b.
  Proof.
    unfold not; intros.
    assert (Hx:=H).
    apply cg_to_dag in H.
    apply hb_inv_cons in H0; auto.
    inversion Hx; subst; clear Hx; simpl_node.
    destruct H0 as [Hx|[(?,[?|Hx])|[(N,Hx)|(Hx,_)]]]; auto;
    try (eapply cg_hb_absurd_node_l in Hx; eauto).
    subst.
    simpl_node.
  Qed.

End DAG.

Module T.

  Definition op_to_cg (o:Trace.op) : op :=
  match o with
  | Trace.MEM _ _ => CONTINUE
  | Trace.FUTURE x => FORK x
  | Trace.FORCE x => JOIN x
  | Trace.INIT => INIT
  end.

  Definition event_to_cg (e:Trace.event) :=
  let (x,o) := e in (x, op_to_cg o).

  Notation CG t := (CG (map event_to_cg t)).
End T.