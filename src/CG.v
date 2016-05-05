Require Import Coq.Lists.List.
Require Import Coq.Relations.Relation_Definitions.
Require Import HJ.Tid.
Require Import HJ.Mid.
Require Import HJ.Cid.
Require Import HJ.Var.
Require Import HJ.Dep.


(* ----- end of boiler-plate code ---- *)

Set Implicit Arguments.

Require Import Aniceto.Graphs.DAG.
Require Import Coq.Relations.Relation_Operators.
Require Aniceto.Graphs.Graph.

Require Import Coq.Structures.OrderedTypeEx.

Require Import Lang.

Module NAT_PAIR := PairOrderedType Nat_as_OT Nat_as_OT.


Module Node.
  Structure node := {
    node_task: tid;
    node_dag_id: nat
  }.

  Definition zero_node t := {| node_task := t; node_dag_id:= 0 |}.
End Node.

Module Trace.
  Inductive op_type := SPAWN | JOIN.

  Structure op := {
    op_t: op_type;
    op_src: tid;
    op_dst: tid
  }.

  Definition trace := list (option op).
End Trace.

Section CG.


Section Defs.
  Import Trace.
  Import Node.

  (** DAG id order *)

  Definition dag_lt x y := node_dag_id x < node_dag_id y.

  Definition edge := (node * node) % type.

  Structure tee := {
    ntype: op_type;
    intra : edge;
    inter : edge
  }.

  Inductive Check : tee -> Prop :=
  | check_spawn:
    forall x y dx last_id,
    dx < last_id ->
    x <> y ->
    Check
    {|
      ntype := SPAWN;
      intra :=
      (
        {| node_task := x; node_dag_id := dx |},
        {| node_task := x; node_dag_id := last_id |}
      );
      inter :=
      (
        {| node_task := x; node_dag_id := dx |},
        {| node_task := y; node_dag_id := S last_id |}
      )
    |}
  | check_join:
    forall x y dx last_id dy,
    dx < last_id ->
    dy < last_id ->
    x <> y ->
    Check
    {|
      ntype := JOIN;
      intra :=
      (
        {| node_task := x; node_dag_id := dx |},
        {| node_task := x; node_dag_id := last_id |}
      );
      inter :=
      (
        {| node_task := y; node_dag_id := dy |},
        {| node_task := x; node_dag_id := last_id |}
      )
    |}.

  (** Creates a future node *)

  Definition tee_last_id (t:tee) :=
  node_dag_id (snd (inter t)).

  Definition mk_spawn last_id (x:node) y :=
  {|
    ntype := SPAWN;
    intra := (x, {| node_task := (node_task x); node_dag_id := S last_id |} );
    inter := (x, {| node_task := y; node_dag_id := S (S last_id) |})
  |}.

  Definition mk_join (last_id:nat) x y :=
  let x' := {| node_task := (node_task x); node_dag_id := S last_id |}
  in {| ntype := JOIN; intra := (x, x'); inter := (y,x') |}.

  Lemma check_intra_eq_task:
    forall v,
    Check v ->
    node_task (fst (intra v)) = node_task (snd (intra v)).
  Proof.
    intros.
    inversion H; simpl in *; auto.
  Qed.

  Lemma check_inter_neq_task:
    forall v,
    Check v ->
    node_task (fst (inter v)) <> node_task (snd (inter v)).
  Proof.
    intros.
    inversion H; simpl in *; auto.
  Qed.

  Lemma check_inter_dag_spawn:
    forall v,
    Check v ->
    ntype v = SPAWN ->
    fst (intra v) = fst (inter v).
  Proof.
    intros.
    inversion H; simpl in *.
    - trivial.
    - rewrite <- H4 in *.
      inversion H0.
  Qed.

  Lemma check_intra_dag_join:
    forall v,
    Check v ->
    ntype v = JOIN ->
    snd (intra v) = snd (inter v).
  Proof.
    intros.
    inversion H; simpl in *; trivial.
    rewrite <- H3 in *.
    inversion H0.
  Qed.

  Lemma check_dag_lt_intra:
    forall v,
    Check v ->
    dag_lt (fst (intra v)) (snd (intra v)).
  Proof.
    intros.
    unfold dag_lt.
    inversion H; simpl in *; auto.
  Qed.

  Lemma check_dag_lt_inter:
    forall v,
    Check v ->
    dag_lt (fst (inter v)) (snd (inter v)).
  Proof.
    intros.
    unfold dag_lt.
    inversion H; simpl in *; auto.
  Qed.

  Lemma check_dag_lt_spawn:
    forall v,
    Check v ->
    ntype v = SPAWN ->
    dag_lt (snd (intra v)) (snd (inter v)).
  Proof.
    intros.
    unfold dag_lt.
    inversion H; simpl in *; auto.
    rewrite <- H4 in *.
    inversion H0.
  Qed.

  Definition to_edges (v:tee) := inter v :: intra v :: nil.

  Definition tee_lookup t v := 
  match v with
  {| ntype := _; intra:=(_,v); inter:=(_,v') |} =>
    if TID.eq_dec (node_task v') t then Some v'
    else if TID.eq_dec (node_task v) t then Some v
    else None
  end.

  Definition tee_contains t v := match tee_lookup t v with Some _ => true | None => false end.

  Structure computation_graph := {
    cg_tees : list tee;
    cg_nodes : MT.t node;
    cg_last_id : nat
  }.

  Definition make_cg t := {|
    cg_tees := nil;
    cg_nodes := MT.add t (Build_node t 0) (@MT.empty node);
    cg_last_id := 0
  |}.

  Definition cg_edges cg :=
  flat_map to_edges (cg_tees cg).

  Definition cg_lookup t cg : option node :=
  MT.find t (cg_nodes cg).

  Definition initial_nodes t := MT.add t (zero_node t) (@MT.empty node).

  Definition cg_nodes_add (t:tee) (m: MT.t node) :=
  match t with
  | {| ntype := SPAWN; intra:=(_,x); inter:=(_,y) |} =>
    (MT.add (node_task x) x)
    (MT.add (node_task y) y m)
  | {| ntype := JOIN; intra:=(_,x); inter:=_ |} => 
    MT.add (node_task x) x m
  end.

  Definition tee_spawn (x y:tid) (cg : computation_graph) : option tee :=
  match cg_lookup x cg with
  | Some nx => Some (mk_spawn (cg_last_id cg) nx y)
  | _ => None
  end.

  Definition tee_join (x y:tid) (cg : computation_graph) : option tee :=
  match (cg_lookup x cg, cg_lookup y cg)  with
  | (Some nx, Some ny) => Some (mk_join (cg_last_id cg) nx ny)
  | _ => None
  end.

  Definition cg_add (v:tee) (cg : computation_graph) : computation_graph :=
    {| cg_tees := v :: cg_tees cg;
       cg_last_id := (tee_last_id v);
       cg_nodes := cg_nodes_add v (cg_nodes cg) |}.

  Definition tee_eval o : computation_graph -> option tee :=
  match o with
  | {| op_t := e; op_src := x; op_dst := y |} =>
    let f := (match e with
    | SPAWN => tee_spawn
    | JOIN => tee_join
    end) in
    f x y
  end.

  Definition cg_eval (o:option op) cg :=
  match o with
  | Some o =>
    match (tee_eval o cg) with
    | Some v => cg_add v cg
    | _ => cg
    end
  | None => cg
  end.

  Inductive Lookup t n cg: Prop :=
  | lookup_def: 
    MT.MapsTo t n (cg_nodes cg) ->
    Lookup t n cg.

  Inductive CG: trace -> computation_graph -> Prop :=
  | cg_nil:
    forall x,
    CG nil (make_cg x)
  | cg_cons:
    forall o l cg,
    CG l cg ->
    CG (o::l) (cg_eval o cg).

  Definition is_evt (o:Lang.op) :=
  match o with
  | Lang.FUTURE _ => true
  | Lang.FORCE _ => true
  | _ => false
  end.

  Definition from_evt e :=
  match e with
  | (x, Lang.FUTURE y) => Some {|op_t:=SPAWN; op_src:=x; op_dst:=y|}
  | (x, Lang.FORCE y) => Some {|op_t:=JOIN; op_src:=x; op_dst:=y|}
  | _ => None
  end.

  Inductive Reduces: computation_graph -> Lang.effect -> computation_graph -> Prop :=
  | reduces_def:
    forall cg e,
    Reduces cg e (cg_eval (from_evt e) cg).

  (**
    Ensure the names are being used properly; no continue edges after a task
    has been termianted (target of a join).
    *)

  Inductive Continue v : edge -> Prop :=
    continue_def:
      Continue v (intra v).

  Inductive Spawn: tee -> edge -> Prop :=
    spawn_def:
      forall v,
      ntype v = SPAWN ->
      Spawn v (inter v).

  Inductive Join: tee -> edge -> Prop :=
    join_def:
      forall v,
      ntype v = JOIN ->
      Join v (inter v).

  Inductive Prec t e : Prop :=
  | prec_continue:
    Continue t e ->
    Prec t e
  | prec_spawn:
    Spawn t e ->
    Prec t e
  | prec_join:
    Join t e ->
    Prec t e.

  Inductive ListEdge {A:Type} {B:Type} P l (e:B*B) : Prop :=
  | list_edge_def:
    forall (x:A),
    List.In x l ->
    P x e ->
    ListEdge P l e.

  Let LContinue := ListEdge Continue.
  Let LSpawn := ListEdge Spawn.
  Let LPrec := ListEdge Prec.

  Require Import Aniceto.Graphs.Graph.

  Variable cg: computation_graph.

  Definition ContinueRefl x := ClosTransRefl (LContinue (cg_tees cg)) x.

  Definition HB := Reaches (LPrec (cg_tees cg)).

  Definition MHP x y : Prop := ~ HB x y /\ ~ HB y x.

  Inductive Ordered n1 n2 : Prop :=
  | ordered_lr:
    HB n1 n2 ->
    Ordered n1 n2
  | ordered_rl:
    HB n2 n1 ->
    Ordered n1 n2.

  (**
    We have a safe-spawn when the body of the spawn may run in parallel
    with the continuation of the spawn.
    *)

  Inductive SafeSpawn : tee -> Prop :=
  | safe_spawn_eq:
    forall v,
    ntype v = SPAWN ->
    List.In v (cg_tees cg) ->
    (forall y, ContinueRefl (snd (inter v)) y -> MHP y (snd (intra v) )) ->
    SafeSpawn v
  | safe_spawn_skip:
    forall v,
    ntype v = JOIN ->
    List.In v (cg_tees cg) ->
    SafeSpawn v.

  Definition Safe := List.Forall SafeSpawn (cg_tees cg).

  (** Is predicate [Safe] equivalent to [CG.RaceFree]? Maybe [CG.RaceFree] implies [Safe] *)
  (** Is predicate [CG.RaceFree] equivalent to [Shadow.RaceFree]? *)

End Defs.

End CG.

Module WellFormed.
  Import Trace.

  Inductive Spawns : trace -> tid -> list tid -> Prop :=
  | spawns_nil:
    forall x,
    Spawns nil x (x::nil)
  | spawns_cons_spawn:
    forall ts l z x y,
    (* x -> y *)
    List.In x l ->
    ~ List.In y l ->
    Spawns ts z l ->
    Spawns (Some {|op_t:=SPAWN; op_src:=x; op_dst:=y |}::ts) z (y::l)
  | spawns_cons_join:
    forall ts l x y z,
    List.In x l ->
    List.In y l ->
    Spawns ts z l ->
    Spawns (Some {|op_t:=JOIN; op_src:=x; op_dst:=y |}::ts) z l
  | spawns_cons_none:
    forall ts l z,
    Spawns ts z l ->
    Spawns (None::ts) z l.

  Lemma spawns_no_dup:
    forall ts x l,
    Spawns ts x l  ->
    NoDup l.
  Proof.
    induction ts; intros. {
      inversion H.
      subst.
      auto using NoDup_cons, NoDup_nil.
    }
    inversion H; subst; clear H; 
    eauto using NoDup_cons.
  Qed.

  Inductive Joins: trace -> list tid -> Prop :=
  | joins_nil:
    Joins nil nil
  | joins_cons_spawn:
    forall ts l x y,
    ~ List.In x l ->
    ~ List.In y l ->
    Joins ts l ->
    Joins (Some {|op_t:=SPAWN; op_src:=x; op_dst:=y |}::ts) l
  | joins_cons_join:
    forall ts l x y,
    ~ List.In x l ->
    Joins ts l ->
    Joins (Some {|op_t:=JOIN; op_src:=x; op_dst:=y |}::ts) l
  | joins_cons_none:
    forall ts l,
    Joins ts l ->
    Joins (None::ts) l.

  Inductive Running : trace -> tid -> list tid -> Prop :=
  | running_nil:
    forall x,
    Running nil x (x::nil)
  | running_cons_spawn:
    forall ts l x y z,
    (* x -> y *)
    List.In x l ->
    ~ List.In y l ->
    Running ts z l ->
    Running (Some {|op_t:=SPAWN; op_src:=x; op_dst:=y |}::ts) z (y::l)
  | running_cons_join:
    forall ts l x y z,
    List.In x l ->
    Running ts z l ->
    Running (Some {|op_t:=JOIN; op_src:=x; op_dst:=y |}::ts) z (remove TID.eq_dec y l)
  | running_cons_none:
    forall ts l z,
    Running ts z l ->
    Running (None::ts) z l.

  Require Import Aniceto.List.

  Lemma running_incl_spawned:
    forall ts ks rs x,
    Running ts x rs ->
    Spawns ts x ks ->
    incl rs ks.
  Proof.
    induction ts; intros. {
      inversion H.
      inversion H0.
      auto using incl_refl.
    }
    inversion H; subst; clear H.
    inversion H0; subst; clear H0.
    - eauto using incl_cons_cons.
    - inversion H0; subst.
      eauto using remove_incl, incl_tran.
    - inversion H0.
      eauto.
  Qed.

  Lemma running_not_in_joins:
    forall ts js rs x,
    Running ts x rs ->
    Joins ts js ->
    forall y, List.In y rs -> ~ List.In y js.
  Proof.
    induction ts; intros. {
      inversion H; inversion H0;
      intuition.
    }
    destruct a as [(a,src,dst)|].
    - destruct a; inversion H; inversion H0; subst; clear H H0.
      + destruct H1; subst; eauto.
      + eauto using remove_in.
    - inversion H; inversion H0; subst; clear H H0.
      eauto.
  Qed.

  Lemma joins_not_in_running:
    forall ts js rs x,
    Running ts x rs ->
    Joins ts js ->
    forall y, List.In y js -> ~ List.In y rs.
  Proof.
    induction ts; intros. {
      inversion H; inversion H0; subst.
      inversion H1.
    }
    destruct a as [(a,src,dst)|].
    - destruct a; inversion H; inversion H0; subst; clear H H0.
      + unfold not; intros Hx.
        destruct Hx.
        * subst.
          contradiction.
        * assert (Hx := IHts _ _ _ H9 H16 _ H1).
          contradiction.
      + unfold not; intros Hx.
        apply remove_in in Hx.
        assert (Hy := IHts _ _ _ H8 H14 _ H1).
        contradiction.
    - inversion H; inversion H0.
      eauto.
  Qed.

  Require Import Coq.Lists.ListSet.
  Require Import Aniceto.ListSet.

  Lemma running_no_dup:
    forall ts rs x,
    Running ts x rs ->
    NoDup rs.
  Proof.
    induction ts; intros; inversion H; subst.
    - auto using no_dup_cons_nil.
    - eauto using NoDup_cons.
    - eauto using no_dup_remove.
    - eauto.
  Qed.

End WellFormed.

Require Import Coq.Structures.OrderedTypeEx.
Require Import Coq.Structures.OrderedType.
Require Import Coq.FSets.FMapAVL.
Module M := FMapAVL.Make Nat_as_OT.

Module Known.
  Import Trace.
  Section Defs.
  Definition known := MT.t (list tid).
  Definition make_known (x:tid) : known := (MT.add x nil (@MT.empty (list tid))).

  Definition spawn (x y:tid) (k:known) : known :=
  match MT.find x k with
  | Some l => (MT.add x (y::l)) (MT.add y l k)
  | _ => k
  end.

  Definition join (x y:tid) (k:known) : known :=
  match (MT.find x k, MT.find y k) with
  | (Some lx,Some ly) =>
    MT.add x (ly ++ lx) k
  | _ => k
  end.

  Definition eval (o:op_type) :=
  match o with SPAWN => spawn | JOIN => join end.

  Inductive Check (k:known) : op -> Prop :=
  | check_spawn:
    forall x y,
    MT.In x k ->
    ~ MT.In y k ->
    Check k {| op_t := SPAWN; op_src:= x; op_dst:= y|}
  | check_join:
    forall x y lx ly,
    MT.MapsTo x lx k ->
    MT.MapsTo y ly k ->
    List.In y lx ->
    ~ List.In x ly ->
    Check k {| op_t := JOIN; op_src := x; op_dst:= y|}.

  Inductive Safe : trace -> tid -> known -> Prop :=
  | safe_nil:
    forall x,
    Safe nil x (make_known x)
  | safe_cons_some:
    forall o x y l k z,
    Check k {| op_t:=o; op_src:=x; op_dst:=y |} ->
    Safe l z k ->
    Safe (Some {| op_t:=o; op_src:=x; op_dst:=y |}::l) z ((eval o) x y k)
  | safe_cons_none:
    forall l z k,
    Safe l z k ->
    Safe (None::l) z k.

  Inductive WellFormed (k:known) :=
  | well_formed_def:
    (forall t l, MT.MapsTo t l k -> ~ List.In t l) ->
    (forall x y l, MT.MapsTo x l k -> List.In y l -> MT.In y k) ->
    WellFormed k.

  Inductive SpawnEdges : trace -> list (tid*tid) -> Prop :=
  | spawn_edges_nil:
    SpawnEdges nil nil
  | spawn_edges_cons_spawn:
    forall x y l e,
    SpawnEdges l e ->
    SpawnEdges (Some {| op_t:=SPAWN; op_src:=x; op_dst:=y|}::l) ((x,y)::e)
  | spawn_edges_cons_join:
    forall l e x y,
    SpawnEdges l e ->
    SpawnEdges (Some {| op_t:=JOIN; op_src:=x; op_dst:=y|}::l) e
  | spawn_edges_cons_none:
    forall l e,
    SpawnEdges l e ->
    SpawnEdges (None::l) e.


  Definition to_spawn_edge e :=
  match e with
  | Some {| op_t:=SPAWN; op_src:=x; op_dst:=y|} => Some (x,y)
  | _ => None
  end.

  Definition spawn_edges (ts:trace) := List.omap to_spawn_edge ts.

  Require Import Bijection.
  Import WellFormed.

  (** The spawn-tree is a DAG *)

  Let spawn_edges_dag:
    forall t a vs es,
    Spawns t a vs ->
    SpawnEdges t es ->
    DAG (Bijection.Lt vs) es.
  Proof.
    induction t; intros;
    inversion H0; subst; clear H0;
    inversion H; subst; clear H; eauto. {
     apply Forall_nil.
    }
    assert (dag: DAG (Lt l) e) by eauto.
    apply Forall_cons.
    - simpl.
      apply in_to_index_of in H3; destruct H3 as (n, (?,?)).
      eauto using index_of_eq, lt_def, index_of_cons.
    - unfold DAG in *.
      apply Forall_impl with (P:=LtEdge (Lt l)); auto.
      intros.
      destruct a as (v,w).
      simpl in *.
      auto using lt_cons.
  Qed.

  Let spawn_supremum:
    forall t a vs es,
    Spawns t a vs ->
    SpawnEdges t es ->
    DAG (Bijection.Lt vs) es ->
    es <> nil ->
    exists x, Graph.In (Edge es) x /\ forall y, ~ Reaches (Edge es) x y.
  Proof.
    intros.
    apply dag_supremum with (Lt := Bijection.Lt vs); auto.
    - auto using TID.eq_dec.
    - eauto using lt_irrefl, spawns_no_dup.
    - eauto using lt_trans, spawns_no_dup.
  Qed.

  Let vertex_mem (vs:list tid) (x:tid) := ListSet.set_mem TID.eq_dec x vs.

  Let edge_mem vs (e:tid*tid) := let (x,y) := e in andb (vertex_mem vs x) (vertex_mem vs y).

  Definition edge_eq_dec := Pair.pair_eq_dec TID.eq_dec.

  Let restrict_vertices vs es := filter (edge_mem vs) es.


  (* TODO: MOVE ME *)
  Lemma in_impl:
    forall {A:Type} (E F:A*A -> Prop) (X:forall e, E e -> F e) (x:A),
    In E x ->
    In F x.
  Proof.
    intros.
    destruct H as (e, (?,?)).
    eauto using in_def.
  Qed.

  Let restrict_vertices_incl:
    forall vs es,
    incl (restrict_vertices vs es) es.
  Proof.
    intros.
    unfold restrict_vertices.
    auto using List.filter_incl.
  Qed.

  Lemma in_incl:
    forall {A:Type} (x:A) l l',
    incl l' l ->
    List.In x l' ->
    List.In x l.
  Proof.
    intros.
    unfold incl in *; auto.
  Qed.

  Let restrict_vertices_in:
    forall rs es x,
    In (Edge (restrict_vertices rs es)) x ->
    In (Edge es) x.
  Proof.
    intros.
    apply in_impl with (E:=Edge (restrict_vertices rs es)); auto.
    intros.
    unfold Edge in *.
    eauto using in_incl, restrict_vertices_incl.
  Qed.

  Let spawn_running_edges_dag:
    forall t a vs rs es,
    Spawns t a vs ->
    Running t a rs ->
    SpawnEdges t es ->
    DAG (Bijection.Lt vs) (restrict_vertices rs es).
  Proof.
    eauto using dag_incl.
  Qed.

  Let spawn_running_supremum:
    forall t a vs rs es,
    Spawns t a vs ->
    Running t a rs ->
    SpawnEdges t es ->
    restrict_vertices rs es <> nil ->
    DAG (Bijection.Lt vs) (restrict_vertices rs es) /\
    exists x, Graph.In (Edge (restrict_vertices rs es)) x /\
    forall y, ~ Reaches (Edge (restrict_vertices rs es)) x y.
  Proof.
    intros.
    assert (DAG (Bijection.Lt vs) (restrict_vertices rs es)) by eauto.
    split; auto.
    intros.
    apply dag_supremum with (Lt := Bijection.Lt vs); auto.
    - auto using TID.eq_dec.
    - eauto using lt_irrefl, spawns_no_dup.
    - eauto using lt_trans, spawns_no_dup.
  Qed.

  Let edge_in_absurd_nil:
    forall {A:Type} (x:A),
    ~ In (Edge nil) x.
  Proof.
    intuition.
    destruct H as (?,(n,?)).
    destruct n.
  Qed.

  Let spawn_edges_to_spawns:
    forall x t a vs es,
    Spawns t a vs ->
    SpawnEdges t es ->
    In (Edge es) x ->
    List.In x vs.
  Proof.
    induction t; intros. {
      inversion H0; subst.
      apply edge_in_absurd_nil in H1.
      inversion H1.
    }
    inversion H; subst; clear H; inversion H0; subst; clear H0; eauto.
    destruct H1 as (e',(He,Hi)).
    destruct He; subst.
    + destruct Hi as [Hi|Hi]; symmetry in Hi; simpl in *; subst; intuition.
    + assert (In (Edge e) x) by eauto using in_def.
      eauto using in_cons.
  Qed.

  Let make_known_mapsto:
    forall x,
    MT.MapsTo x nil (make_known x).
  Proof.
    intros.
    unfold make_known.
    auto using MT.add_1.
  Qed.

  Let make_known_inv_maps_to:
    forall x y l,
    MT.MapsTo x l (make_known y) ->
    x = y /\ l = nil.
  Proof.
    intros.
    unfold make_known in *.
    apply MT_Facts.add_mapsto_iff in H.
    destruct H as [(?,?)|(?,?)]; auto.
    apply MT_Facts.empty_mapsto_iff in H0.
    contradiction.
  Qed.

  Let spawn_inv_maps_to:
    forall x y z l k,
    MT.MapsTo z l (spawn x y k) ->
    MT.MapsTo z l k \/
    (z = x /\ exists l', l = y :: l' /\ MT.MapsTo x l' k) \/
    (x <> z /\ y = z /\ MT.MapsTo x l k).
  Proof.
    intros.
    unfold spawn in *.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He in *.
    - auto.
    - apply MT_Facts.add_mapsto_iff in H.
      destruct H as [(?,?)|(?,?)].
      + right; left.
        intuition.
        exists x0.
        intuition.
      + apply MT_Facts.add_mapsto_iff in H1.
        destruct H1 as [(?,?)|(?,?)].
        * right; right.
          subst; auto.
        * intuition.
  Qed.

  Let join_inv_maps_to:
    forall x y z l k,
    MT.MapsTo z l (join x y k) ->
    MT.MapsTo z l k \/
    (exists lx ly, MT.MapsTo x lx k /\ MT.MapsTo y ly k /\ l = ly ++ lx /\ z = x).
  Proof.
    unfold join.
    intros.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He in *. {
      intuition.
    }
    destruct (MT_Extra.find_rw y k) as [(He',n)|(?,(He',?))]; rewrite He' in *. {
      intuition.
    }
    clear He He'.
    apply MT_Facts.add_mapsto_iff in H.
    destruct H as [(?,?)|(?,?)].
    - subst.
      right.
      exists x0.
      eauto.
    - intuition.
  Qed.

  Let spawn_mapsto_neq:
    forall (x y:tid) l (k:known),
    y <> x ->
    MT.MapsTo x l k ->
    MT.MapsTo y l (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He.
    - contradiction n; eauto using MT_Extra.mapsto_to_in.
    - assert (x0 = l) by eauto using MT_Facts.MapsTo_fun; subst.
      eauto using MT.add_2, MT.add_1.
  Qed.

  Let spawn_mapsto_inv_1:
    forall x y l k,
    MT.In x k ->
    MT.MapsTo x l (spawn x y k) ->
    exists l', (l = y::l' /\ MT.MapsTo x l' k).
  Proof.
    unfold spawn.
    intros.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He in *.
    - contradiction.
    - apply MT_Facts.add_mapsto_iff in H0.
      destruct H0 as [(?,?)|(?,?)].
      + subst.
        eauto.
      + contradiction H0; auto.
  Qed.

  Let spawn_mapsto_eq:
    forall x y k l,
    MT.MapsTo x l k ->
    MT.MapsTo x (y::l) (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He.
    - contradiction n; eauto using MT_Extra.mapsto_to_in.
    - assert (x0 = l) by eauto using MT_Facts.MapsTo_fun; subst.
      eauto using MT.add_1.
  Qed.

  Let spawn_mapsto_eq_spawned:
    forall x y k l,
    MT.MapsTo x l k ->
    x <> y ->
    MT.MapsTo y l (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He.
    - contradiction n; eauto using MT_Extra.mapsto_to_in.
    - assert (x0 = l) by eauto using MT_Facts.MapsTo_fun; subst.
      eauto using MT.add_2, MT.add_1.
  Qed.

  Let spawn_mapsto_eq_spawner:
    forall x y k l,
    MT.In x k ->
    x <> y ->
    MT.MapsTo y l (spawn x y k) ->
    MT.MapsTo x l k.
  Proof.
    intros.
    unfold spawn in *.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He in *.
    - contradiction n; eauto using MT_Extra.mapsto_to_in.
    - clear He H.
      apply MT_Facts.add_mapsto_iff in H1.
      destruct H1 as [(?,?)|(?,?)].
      + contradiction.
      + apply MT_Facts.add_mapsto_iff in H1.
        destruct H1 as [(?,?)|(?,?)]; subst; auto.
        contradiction H1; trivial.
  Qed.

  Let spawn_mapsto_neq_neq:
    forall x y z l k,
    z <> x ->
    z <> y ->
    MT.MapsTo z l k ->
    MT.MapsTo z l (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He.
    - auto.
    - eauto using MT.add_2.
  Qed.

  Let spawn_mapsto_inv_neq_neq:
    forall x y z l k,
    z <> x ->
    z <> y ->
    MT.MapsTo z l (spawn x y k) ->
    MT.MapsTo z l k.
  Proof.
    unfold spawn.
    intros.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))]; rewrite He in *.
    - auto.
    - repeat (apply MT.add_3 in H1; auto).
  Qed.

  Let spawn_in:
    forall x y z k,
    MT.In z k ->
    MT.In z (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))];
    rewrite He;
    auto using MT_Extra.add_in.
  Qed.

  Let spawn_in_spawned:
    forall x y k,
    MT.In x k ->
    MT.In y (spawn x y k).
  Proof.
    intros.
    unfold spawn.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))];
    rewrite He.
    - contradiction.
    - apply MT_Extra.add_in.
      rewrite MT_Facts.add_in_iff.
      auto.
  Qed.

  Let join_in:
    forall x y z k,
    MT.In z k ->
    MT.In z (join x y k).
  Proof.
    intros.
    unfold join.
    destruct (MT_Extra.find_rw x k) as [(He,n)|(?,(He,?))];
    rewrite He.
    - auto.
    - clear He.
      destruct (MT_Extra.find_rw y k) as [(He,n)|(?,(He,?))];
      rewrite He;
    auto using MT_Extra.add_in.
  Qed.

  Let in_spawns_in_known:
    forall t x a vs k,
    Spawns t a vs ->
    Safe t a k ->
    List.In x vs ->
    MT.In x k.
  Proof.
    induction t; intros. {
      inversion H; subst.
      inversion H1.
      - subst.
        inversion H0; subst.
        eauto using make_known_mapsto, MT_Extra.mapsto_to_in.
      - inversion H2.
    }
    inversion H; subst; clear H; inversion H0; subst; clear H0; simpl; eauto.
    destruct H1.
    + subst.
      simpl.
      assert (x0 <> x). {
        intuition; subst.
        contradiction.
      }
      inversion H10; subst.
      apply MT_Extra.in_to_mapsto in H2.
      destruct H2 as (l', Hmt).
      assert (MT.MapsTo x l' (spawn x0 x k0)) by eauto using spawn_mapsto_neq.
      eauto using MT_Extra.mapsto_to_in.
    + simpl; eauto.
  Qed.

  Let make_known_is_well_formed:
    forall x,
    WellFormed (make_known x).
  Proof.
    intros.
    apply well_formed_def.
    - intros.
      apply make_known_inv_maps_to in H; destruct H; subst.
      auto.
    - intros.
      apply make_known_inv_maps_to in H; destruct H; subst.
      inversion H0.
  Qed.

  Let well_formed_not_refl:
    forall x l k,
    WellFormed k ->
    MT.MapsTo x l k ->
    ~ List.In x l.
  Proof.
    intros; inversion H; eauto.
  Qed.

  Let well_formed_range_in_dom:
    forall x y l k,
    WellFormed k ->
    MT.MapsTo x l k ->
    List.In y l ->
    MT.In y k.
  Proof.
    intros; inversion H; eauto.
  Qed.

  Let spawn_is_well_formed:
    forall x y k,
    WellFormed k ->
    ~ MT.In y k ->
    WellFormed (spawn x y k).
  Proof.
    intros.
    apply well_formed_def; intros. {
    intros.
    apply spawn_inv_maps_to in H1.
    destruct H1 as [?|[(?,(?,(?,?)))|(?,(?,?))]]; subst; auto.
    - eauto.
    - unfold not; intros.
      destruct H1.
      + subst.
        contradiction H0.
        eauto using MT_Extra.mapsto_to_in.
      + assert (~ List.In x x0) by eauto.
        contradiction.
    - unfold not; intros.
      contradiction H0.
      eauto.
    }
    apply spawn_inv_maps_to in H1.
    destruct H1 as [?|[(?,(?,(?,?)))|(?,(?,?))]]; subst; eauto.
    destruct H2; subst; eauto using MT_Extra.mapsto_to_in.
  Qed.
(*
  Let well_formed_inv_spawn:
    forall x y k,
    ~ MT.In y k ->
    WellFormed (spawn x y k) ->
    WellFormed k.
  Proof.
    intros.
    inversion H0.
    apply well_formed_def; intros.
    - destruct (TID.eq_dec t x), (TID.eq_dec t y); rewrite tid_eq_rw in *; auto; repeat subst.
      + apply spawn_mapsto_eq with (y:=y) in H3.
        apply well_formed_not_refl in H3; auto.
        contradiction H3; auto using in_eq.
      + apply spawn_mapsto_eq with (y:=y) in H3.
        apply well_formed_not_refl in H3; auto.
        unfold not; intros.
        contradiction H3; auto using in_cons.
      + assert (N: ~ MT.In y k) by eauto.
        contradiction N; eauto using MT_Extra.mapsto_to_in.
    - destruct (TID.eq_dec y0 x0); rewrite tid_eq_rw in *; auto; repeat subst.
      + eauto using MT_Extra.mapsto_to_in.
      + assert 
        assert (MT.In y (spawn x y k)). {
          apply H2 with (x:=x0) (l:=l).
        }

  Qed.
*)
  Let join_is_well_formed:
    forall x y l k,
    WellFormed k ->
    MT.MapsTo y l k ->
    ~ List.In x l ->
    WellFormed (join x y k).
  Proof.
    intros.
    apply well_formed_def.
    - intros.
      apply join_inv_maps_to in H2.
      destruct H2 as [?|(?,(?,(?,(?,(?,?)))))].
      + eauto.
      + subst.
        assert (x1 = l) by eauto using MT_Facts.MapsTo_fun; subst.
        unfold not; intros.
        apply in_app_iff in H4.
        destruct H4.
        * contradiction.
        * assert (~ List.In x x0) by eauto.
          contradiction.
    - intros.
      apply join_inv_maps_to in H2.
      destruct H2 as [?|(?,(?,(?,(?,(?,?)))))].
      + eauto.
      + subst.
        apply in_app_iff in H3; destruct H3; eauto.
  Qed.

  Let safe_to_well_formed:
    forall t x k,
    Safe t x k ->
    WellFormed k.
  Proof.
    induction t; intros. {
      inversion H; subst; auto.
    }
    inversion H; subst; clear H.
    - destruct o.
      + simpl.
        inversion H2; eauto.
      + simpl.
        inversion H2; eauto.
    - eauto.
  Qed.

  (* This does not hold: 
  Let known_to_spawn_edge:
    forall t a es k l x y,
    SpawnEdges t es ->
    Safe t a k ->
    MT.MapsTo x l k ->
    List.In y l ->
    Edge es (x, y).
  *)


  (** TODO: Move me *)
  Lemma reaches_impl:
    forall {A:Type} (x y:A) (E F:(A*A)->Prop),
    (forall e, E e -> F e) ->
    Reaches E x y ->
    Reaches F x y.
  Proof.
    intros.
    inversion H0.
    eauto using walk2_impl, reaches_def.
  Qed.

  Let edge_cons:
    forall {A:Type} es (e e':A*A),
    Edge es e ->
    Edge (e' :: es) e.
  Proof.
    unfold Edge.
    auto using in_cons.
  Qed.

  Let reaches_cons:
    forall {A:Type} (x y:A) e es,
    Reaches (Edge es) x y ->
    Reaches (Edge (e :: es)) x y.
  Proof.
    eauto using reaches_impl.
  Qed.

  Lemma edge_to_reaches:
    forall {A:Type} (x y:A) (E:A*A->Prop),
    E (x,y) ->
    Reaches E x y.
  Proof.
    intros.
    eauto using reaches_def, edge_to_walk2.
  Qed.

  Let known_to_spawn_edge:
    forall t a es k l x y,
    SpawnEdges t es ->
    Safe t a k ->
    MT.MapsTo x l k ->
    List.In y l ->
    WellFormed k ->
    Reaches (Edge es) x y.
  Proof.
    induction t; intros. {
      inversion H0; subst.
      assert (X: x = a /\ l = nil) by eauto.
      destruct X; subst.
      inversion H2.
    }
    inversion H; subst; clear H.
    - inversion H0; subst; clear H0.
      inversion H10; subst; clear H10.
      simpl in *.
      destruct (TID.eq_dec x x0), (TID.eq_dec y y0); rewrite tid_eq_rw in *; subst.
      + apply edge_to_reaches.
        unfold Edge.
        auto using in_eq.
      + apply spawn_mapsto_inv_1 in H1; auto.
        destruct H1 as (l', (?,?)); subst.
        assert (List.In y l'). {
          destruct H2.
          - contradiction n; auto.
          - auto.
        }
        eauto.
      + assert (X: MT.MapsTo x l k0 \/ x = y0 /\ MT.MapsTo x0 l k0). {
          apply spawn_inv_maps_to in H1.
          destruct H1 as [?|[(?,(?,(?,?)))|(?,(?,?))]]; subst; auto.
          contradiction n; auto.
        }
        destruct X as [?|(?,?)].
        * eauto.
        * subst.
          contradiction H5.
          eauto.
      + destruct (TID.eq_dec x y0); rewrite tid_eq_rw in *; subst. {
          apply spawn_mapsto_eq_spawner in H1; auto.
          assert (Reaches (Edge e) x0 y) by eauto.
          unfold not; intros.
          subst.
        }
        apply spawn_mapsto_inv_neq_neq in H1; auto.
        eauto.
        unfold not; intros.
        subst.
  Qed.

  Let progress:
    forall t a vs rs es k,
    Spawns t a vs ->
    Running t a rs ->
    SpawnEdges t es ->
    Safe t a k ->
    restrict_vertices rs es <> nil ->
    exists x l, MT.MapsTo x l k /\ forall y, List.In y l -> ~ List.In y rs.
  Proof.
    intros.
    assert (Hx: DAG (Bijection.Lt vs) (restrict_vertices rs es) /\
    exists x, Graph.In (Edge (restrict_vertices rs es)) x /\
    forall y, ~ Reaches (Edge (restrict_vertices rs es)) x y) by eauto.
    destruct Hx as (Hx, (x, (Hin, Hy))).
    exists x.
    assert (i: MT.In x k) by eauto using in_spawns_in_known.
    apply MT_Extra.in_to_mapsto in i.
    destruct i as (l, mt).
    exists l.
    split; auto.
    intros.
    assert (~ Reaches (Edge (restrict_vertices rs es)) x y) by eauto; clear Hy.
    assert (Edge es (x, y)). {
      unfold Edge in *.
      
    }
    unfold not; intros.
    
  Qed.

End Defs.
End Known.
