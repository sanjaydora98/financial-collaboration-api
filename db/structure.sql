\restrict psYgiFSU03fpkqhpOFeOyNzdbukVlcsfpL0He3XDh5FQDmrd0KfdyGHIMcVAo5r

-- Dumped from database version 14.22 (Homebrew)
-- Dumped by pg_dump version 14.22 (Homebrew)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    expense_id bigint NOT NULL,
    actor_membership_id bigint,
    actor_type character varying NOT NULL,
    category character varying NOT NULL,
    event_type character varying NOT NULL,
    change_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    request_id character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT audit_logs_actor_valid CHECK (((((actor_type)::text = 'user'::text) AND (actor_membership_id IS NOT NULL)) OR (((actor_type)::text = 'system'::text) AND (actor_membership_id IS NULL)))),
    CONSTRAINT audit_logs_category_event_valid CHECK (((((category)::text = 'crud'::text) AND ((event_type)::text = ANY ((ARRAY['create'::character varying, 'update'::character varying, 'delete'::character varying])::text[]))) OR (((category)::text = 'workflow'::text) AND ((event_type)::text = ANY ((ARRAY['submitted'::character varying, 'approved'::character varying, 'rejected'::character varying, 'reimbursement_paid'::character varying, 'import_accepted'::character varying, 'reimbursement_initiated'::character varying, 'reimbursement_failed'::character varying])::text[])))))
);


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token_digest character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT auth_sessions_token_digest_nonblank CHECK ((btrim((token_digest)::text) <> ''::text))
);


--
-- Name: auth_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auth_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auth_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auth_sessions_id_seq OWNED BY public.auth_sessions.id;


--
-- Name: expense_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_approvals (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    expense_id bigint NOT NULL,
    step smallint NOT NULL,
    stage character varying NOT NULL,
    approver_membership_id bigint NOT NULL,
    status character varying NOT NULL,
    acted_at timestamp with time zone,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT expense_approvals_decision_timestamp_valid CHECK (((((status)::text = ANY ((ARRAY['queued'::character varying, 'pending'::character varying])::text[])) AND (acted_at IS NULL)) OR (((status)::text = ANY ((ARRAY['approved'::character varying, 'rejected'::character varying, 'skipped'::character varying])::text[])) AND (acted_at IS NOT NULL)))),
    CONSTRAINT expense_approvals_rejection_reason_valid CHECK (((((status)::text = 'rejected'::text) AND (rejection_reason IS NOT NULL) AND (btrim(rejection_reason) <> ''::text)) OR (((status)::text <> 'rejected'::text) AND (rejection_reason IS NULL)))),
    CONSTRAINT expense_approvals_status_valid CHECK (((status)::text = ANY ((ARRAY['queued'::character varying, 'pending'::character varying, 'approved'::character varying, 'rejected'::character varying, 'skipped'::character varying])::text[]))),
    CONSTRAINT expense_approvals_step_positive CHECK ((step > 0)),
    CONSTRAINT expense_approvals_step_stage_valid CHECK ((((step = 1) AND ((stage)::text = 'manager'::text)) OR ((step = 2) AND ((stage)::text = 'finance'::text))))
);


--
-- Name: expense_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.expense_approvals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expense_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.expense_approvals_id_seq OWNED BY public.expense_approvals.id;


--
-- Name: expenses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expenses (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    creator_membership_id bigint NOT NULL,
    member_membership_id bigint NOT NULL,
    imported_transaction_id bigint,
    amount numeric(12,2) NOT NULL,
    currency character varying(3) NOT NULL,
    merchant character varying NOT NULL,
    description text,
    category character varying,
    incurred_on date NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    submitted_at timestamp with time zone,
    deleted_at timestamp with time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT expenses_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT expenses_currency_format CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT expenses_lock_version_nonnegative CHECK ((lock_version >= 0)),
    CONSTRAINT expenses_merchant_nonblank CHECK ((btrim((merchant)::text) <> ''::text)),
    CONSTRAINT expenses_status_valid CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'submitted'::character varying, 'approved'::character varying, 'rejected'::character varying, 'reimbursed'::character varying])::text[])))
);


--
-- Name: expenses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.expenses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: expenses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.expenses_id_seq OWNED BY public.expenses.id;


--
-- Name: imported_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.imported_transactions (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    import_id bigint NOT NULL,
    provider character varying NOT NULL,
    external_account_ref character varying NOT NULL,
    external_transaction_id character varying NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency character varying(3) NOT NULL,
    merchant character varying NOT NULL,
    description text,
    transaction_date date NOT NULL,
    raw_payload jsonb,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    reviewed_by_membership_id bigint,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    category character varying,
    CONSTRAINT imported_transactions_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT imported_transactions_currency_format CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT imported_transactions_review_fields_valid CHECK (((((status)::text = 'pending'::text) AND (reviewed_by_membership_id IS NULL) AND (reviewed_at IS NULL) AND (rejection_reason IS NULL)) OR (((status)::text = 'accepted'::text) AND (reviewed_by_membership_id IS NOT NULL) AND (reviewed_at IS NOT NULL) AND (rejection_reason IS NULL)) OR (((status)::text = 'rejected'::text) AND (reviewed_by_membership_id IS NOT NULL) AND (reviewed_at IS NOT NULL) AND (rejection_reason IS NOT NULL) AND (btrim(rejection_reason) <> ''::text)))),
    CONSTRAINT imported_transactions_source_fields_nonblank CHECK (((btrim((provider)::text) <> ''::text) AND (btrim((external_account_ref)::text) <> ''::text) AND (btrim((external_transaction_id)::text) <> ''::text) AND (btrim((merchant)::text) <> ''::text))),
    CONSTRAINT imported_transactions_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'accepted'::character varying, 'rejected'::character varying])::text[])))
);


--
-- Name: imported_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.imported_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: imported_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.imported_transactions_id_seq OWNED BY public.imported_transactions.id;


--
-- Name: imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.imports (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    requested_by_membership_id bigint NOT NULL,
    provider character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    error_summary text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT imports_provider_key_nonblank CHECK (((btrim((provider)::text) <> ''::text) AND (btrim((idempotency_key)::text) <> ''::text))),
    CONSTRAINT imports_status_valid CHECK (((status)::text = ANY ((ARRAY['queued'::character varying, 'running'::character varying, 'completed'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.imports_id_seq OWNED BY public.imports.id;


--
-- Name: reimbursements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reimbursements (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    expense_id bigint NOT NULL,
    initiated_by_membership_id bigint NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency character varying(3) NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    external_reference character varying,
    paid_at timestamp with time zone,
    failure_reason text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT reimbursements_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT reimbursements_currency_format CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT reimbursements_failure_reason_valid CHECK (((((status)::text = 'failed'::text) AND (failure_reason IS NOT NULL) AND (btrim(failure_reason) <> ''::text)) OR (((status)::text <> 'failed'::text) AND (failure_reason IS NULL)))),
    CONSTRAINT reimbursements_paid_timestamp_valid CHECK (((((status)::text = 'paid'::text) AND (paid_at IS NOT NULL)) OR (((status)::text <> 'paid'::text) AND (paid_at IS NULL)))),
    CONSTRAINT reimbursements_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'paid'::character varying, 'failed'::character varying, 'cancelled'::character varying])::text[])))
);


--
-- Name: reimbursements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reimbursements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reimbursements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reimbursements_id_seq OWNED BY public.reimbursements.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    user_id bigint NOT NULL,
    role character varying NOT NULL,
    approval_stage character varying,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT team_memberships_role_approval_stage_valid CHECK (((((role)::text = ANY ((ARRAY['creator'::character varying, 'viewer'::character varying])::text[])) AND (approval_stage IS NULL)) OR (((role)::text = 'approver'::text) AND (approval_stage IS NOT NULL) AND ((approval_stage)::text = ANY ((ARRAY['manager'::character varying, 'finance'::character varying])::text[]))) OR (((role)::text = 'admin'::text) AND ((approval_stage IS NULL) OR ((approval_stage)::text = ANY ((ARRAY['manager'::character varying, 'finance'::character varying])::text[])))))),
    CONSTRAINT team_memberships_role_valid CHECK (((role)::text = ANY ((ARRAY['creator'::character varying, 'approver'::character varying, 'viewer'::character varying, 'admin'::character varying])::text[])))
);


--
-- Name: team_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_memberships_id_seq OWNED BY public.team_memberships.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id bigint NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    created_by_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT teams_name_slug_nonblank CHECK (((btrim((name)::text) <> ''::text) AND (btrim((slug)::text) <> ''::text)))
);


--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.teams_id_seq OWNED BY public.teams.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    password_digest character varying NOT NULL,
    disabled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT users_email_name_nonblank CHECK ((((email)::text = lower((email)::text)) AND (btrim((email)::text) <> ''::text) AND (btrim((name)::text) <> ''::text)))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: auth_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions ALTER COLUMN id SET DEFAULT nextval('public.auth_sessions_id_seq'::regclass);


--
-- Name: expense_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_approvals ALTER COLUMN id SET DEFAULT nextval('public.expense_approvals_id_seq'::regclass);


--
-- Name: expenses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses ALTER COLUMN id SET DEFAULT nextval('public.expenses_id_seq'::regclass);


--
-- Name: imported_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imported_transactions ALTER COLUMN id SET DEFAULT nextval('public.imported_transactions_id_seq'::regclass);


--
-- Name: imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports ALTER COLUMN id SET DEFAULT nextval('public.imports_id_seq'::regclass);


--
-- Name: reimbursements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reimbursements ALTER COLUMN id SET DEFAULT nextval('public.reimbursements_id_seq'::regclass);


--
-- Name: team_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships ALTER COLUMN id SET DEFAULT nextval('public.team_memberships_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams ALTER COLUMN id SET DEFAULT nextval('public.teams_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_pkey PRIMARY KEY (id);


--
-- Name: expense_approvals expense_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_approvals
    ADD CONSTRAINT expense_approvals_pkey PRIMARY KEY (id);


--
-- Name: expenses expenses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);


--
-- Name: imported_transactions imported_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imported_transactions
    ADD CONSTRAINT imported_transactions_pkey PRIMARY KEY (id);


--
-- Name: imports imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports
    ADD CONSTRAINT imports_pkey PRIMARY KEY (id);


--
-- Name: reimbursements reimbursements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reimbursements
    ADD CONSTRAINT reimbursements_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: team_memberships team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT team_memberships_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_active_team_approvers_on_team_and_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_team_approvers_on_team_and_stage ON public.team_memberships USING btree (team_id, approval_stage) WHERE (active AND (approval_stage IS NOT NULL) AND ((role)::text = ANY ((ARRAY['approver'::character varying, 'admin'::character varying])::text[])));


--
-- Name: index_audit_logs_on_expense_history; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_expense_history ON public.audit_logs USING btree (team_id, expense_id, created_at, id);


--
-- Name: index_auth_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_auth_sessions_on_token_digest ON public.auth_sessions USING btree (token_digest);


--
-- Name: index_auth_sessions_on_user_id_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_auth_sessions_on_user_id_and_expires_at ON public.auth_sessions USING btree (user_id, expires_at);


--
-- Name: index_expense_approvals_on_approver_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_expense_approvals_on_approver_queue ON public.expense_approvals USING btree (team_id, approver_membership_id, status, created_at);


--
-- Name: index_expense_approvals_on_expense_step_approver; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_expense_approvals_on_expense_step_approver ON public.expense_approvals USING btree (team_id, expense_id, step, approver_membership_id);


--
-- Name: index_expenses_on_imported_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_expenses_on_imported_transaction_id ON public.expenses USING btree (imported_transaction_id);


--
-- Name: index_expenses_on_team_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_expenses_on_team_and_id ON public.expenses USING btree (team_id, id);


--
-- Name: index_expenses_on_team_creator_status_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_expenses_on_team_creator_status_created ON public.expenses USING btree (team_id, creator_membership_id, status, created_at);


--
-- Name: index_expenses_on_team_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_expenses_on_team_id_and_status_and_created_at ON public.expenses USING btree (team_id, status, created_at);


--
-- Name: index_expenses_on_team_member_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_expenses_on_team_member_and_created_at ON public.expenses USING btree (team_id, member_membership_id, created_at);


--
-- Name: index_imported_transactions_on_external_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_imported_transactions_on_external_identity ON public.imported_transactions USING btree (team_id, provider, external_account_ref, external_transaction_id);


--
-- Name: index_imported_transactions_on_team_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_imported_transactions_on_team_and_id ON public.imported_transactions USING btree (team_id, id);


--
-- Name: index_imports_on_team_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_imports_on_team_and_id ON public.imports USING btree (team_id, id);


--
-- Name: index_imports_on_team_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_imports_on_team_id_and_status_and_created_at ON public.imports USING btree (team_id, status, created_at);


--
-- Name: index_imports_on_team_provider_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_imports_on_team_provider_idempotency ON public.imports USING btree (team_id, provider, idempotency_key);


--
-- Name: index_pending_imported_transactions_by_team_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_pending_imported_transactions_by_team_date ON public.imported_transactions USING btree (team_id, transaction_date) WHERE ((status)::text = 'pending'::text);


--
-- Name: index_reimbursements_on_team_id_and_expense_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_reimbursements_on_team_id_and_expense_id ON public.reimbursements USING btree (team_id, expense_id);


--
-- Name: index_reimbursements_on_team_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_reimbursements_on_team_id_and_status_and_created_at ON public.reimbursements USING btree (team_id, status, created_at);


--
-- Name: index_team_memberships_on_team_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_memberships_on_team_and_id ON public.team_memberships USING btree (team_id, id);


--
-- Name: index_team_memberships_on_team_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_memberships_on_team_id_and_user_id ON public.team_memberships USING btree (team_id, user_id);


--
-- Name: index_team_memberships_on_user_id_and_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_user_id_and_team_id ON public.team_memberships USING btree (user_id, team_id);


--
-- Name: index_teams_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_slug ON public.teams USING btree (slug);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: audit_logs fk_audit_logs_actor_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_audit_logs_actor_same_team FOREIGN KEY (team_id, actor_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: audit_logs fk_audit_logs_expense_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_audit_logs_expense_same_team FOREIGN KEY (team_id, expense_id) REFERENCES public.expenses(team_id, id) ON DELETE RESTRICT;


--
-- Name: expense_approvals fk_expense_approvals_approver_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_approvals
    ADD CONSTRAINT fk_expense_approvals_approver_same_team FOREIGN KEY (team_id, approver_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: expense_approvals fk_expense_approvals_expense_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_approvals
    ADD CONSTRAINT fk_expense_approvals_expense_same_team FOREIGN KEY (team_id, expense_id) REFERENCES public.expenses(team_id, id) ON DELETE RESTRICT;


--
-- Name: expenses fk_expenses_creator_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_expenses_creator_same_team FOREIGN KEY (team_id, creator_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: expenses fk_expenses_imported_transaction_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_expenses_imported_transaction_same_team FOREIGN KEY (team_id, imported_transaction_id) REFERENCES public.imported_transactions(team_id, id) ON DELETE RESTRICT;


--
-- Name: expenses fk_expenses_member_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_expenses_member_same_team FOREIGN KEY (team_id, member_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: imported_transactions fk_imported_transactions_import_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imported_transactions
    ADD CONSTRAINT fk_imported_transactions_import_same_team FOREIGN KEY (team_id, import_id) REFERENCES public.imports(team_id, id) ON DELETE RESTRICT;


--
-- Name: imported_transactions fk_imported_transactions_reviewer_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imported_transactions
    ADD CONSTRAINT fk_imported_transactions_reviewer_same_team FOREIGN KEY (team_id, reviewed_by_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: imports fk_imports_requester_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports
    ADD CONSTRAINT fk_imports_requester_same_team FOREIGN KEY (team_id, requested_by_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- Name: reimbursements fk_rails_2bc497689c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reimbursements
    ADD CONSTRAINT fk_rails_2bc497689c FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: auth_sessions fk_rails_4aba5b3f33; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT fk_rails_4aba5b3f33 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: expense_approvals fk_rails_56f2598f16; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_approvals
    ADD CONSTRAINT fk_rails_56f2598f16 FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: team_memberships fk_rails_5aba9331a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_5aba9331a7 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: expenses fk_rails_7585ff2d31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expenses
    ADD CONSTRAINT fk_rails_7585ff2d31 FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: imports fk_rails_8be1fecf9f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports
    ADD CONSTRAINT fk_rails_8be1fecf9f FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: teams fk_rails_a068b3a692; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_a068b3a692 FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: imported_transactions fk_rails_a34ca502a4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imported_transactions
    ADD CONSTRAINT fk_rails_a34ca502a4 FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: audit_logs fk_rails_eaead0bdbc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_eaead0bdbc FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE RESTRICT;


--
-- Name: reimbursements fk_reimbursements_expense_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reimbursements
    ADD CONSTRAINT fk_reimbursements_expense_same_team FOREIGN KEY (team_id, expense_id) REFERENCES public.expenses(team_id, id) ON DELETE RESTRICT;


--
-- Name: reimbursements fk_reimbursements_initiator_same_team; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reimbursements
    ADD CONSTRAINT fk_reimbursements_initiator_same_team FOREIGN KEY (team_id, initiated_by_membership_id) REFERENCES public.team_memberships(team_id, id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict psYgiFSU03fpkqhpOFeOyNzdbukVlcsfpL0He3XDh5FQDmrd0KfdyGHIMcVAo5r

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260930164312'),
('20260930162502'),
('20260930154008'),
('20260930153743'),
('20260930153204');

