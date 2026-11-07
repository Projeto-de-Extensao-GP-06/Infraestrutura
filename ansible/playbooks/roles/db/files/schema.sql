SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
DROP DATABASE IF EXISTS sgpj;
CREATE DATABASE sgpj;
USE sgpj;

-- =========================================================
-- TABELAS DE DOMÍNIO
-- =========================================================

CREATE TABLE status_cliente (
                                id INT AUTO_INCREMENT PRIMARY KEY,
                                nome VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE tipo_documento (
                                id INT AUTO_INCREMENT PRIMARY KEY,
                                nome VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE prioridade (
                            id INT AUTO_INCREMENT PRIMARY KEY,
                            nome VARCHAR(50) NOT NULL
);

CREATE TABLE fase_processo (
                               id INT AUTO_INCREMENT PRIMARY KEY,
                               nome VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE sigla_tribunal (
                                id INT AUTO_INCREMENT PRIMARY KEY,
                                sigla_tribunal VARCHAR(10) NOT NULL UNIQUE
);

CREATE TABLE tipo_alteracao (
                                id INT AUTO_INCREMENT PRIMARY KEY,
                                nome VARCHAR(70) NOT NULL UNIQUE
);

CREATE TABLE motivo_status_processo (
                                        id          INT AUTO_INCREMENT PRIMARY KEY,
                                        nome        VARCHAR(100) NOT NULL UNIQUE,
                                        aplicavel_a ENUM('SUSPENSO', 'ENCERRADO', 'AMBOS') NOT NULL
);

CREATE TABLE permissao (
                           id INT AUTO_INCREMENT PRIMARY KEY,
                           nome VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE microsoft_token_config (
                                        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
                                        refresh_token TEXT NULL,
                                        data_criacao DATETIME NULL
);

-- =========================================================
-- TABELAS BASE
-- =========================================================

CREATE TABLE endereco (
                          id BIGINT AUTO_INCREMENT PRIMARY KEY,
                          cep VARCHAR(10),
                          logradouro VARCHAR(150) NOT NULL,
                          numero VARCHAR(10) NOT NULL,
                          bairro VARCHAR(100) NOT NULL,
                          cidade VARCHAR(100) NOT NULL,
                          estado CHAR(2) NOT NULL,
                          complemento VARCHAR(100)
);

CREATE TABLE padrao_caminho_armazenamento (
                                              id BIGINT AUTO_INCREMENT PRIMARY KEY,
                                              cliente_id BIGINT NOT NULL,
                                              caminho_base VARCHAR(255) NOT NULL UNIQUE
);

-- =========================================================
-- USUÁRIO E CARGO
-- =========================================================

CREATE TABLE cargo (
                       id INT AUTO_INCREMENT PRIMARY KEY,
                       nome VARCHAR(90) NOT NULL UNIQUE,
                       criado_por BIGINT,
                       criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE usuario (
                         id BIGINT AUTO_INCREMENT PRIMARY KEY,
                         nome VARCHAR(100) NOT NULL,
                         email VARCHAR(255) NOT NULL UNIQUE,
                         senha VARCHAR(255),
                         cargo_id INT,
                         criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                         ativo TINYINT NOT NULL DEFAULT 1,

                         FOREIGN KEY (cargo_id) REFERENCES cargo(id)
);

CREATE TABLE usuario_refresh_token (
                                       id BIGINT AUTO_INCREMENT PRIMARY KEY,
                                       token VARCHAR(255) NOT NULL UNIQUE,
                                       usuario_id BIGINT NOT NULL,
                                       expira_em DATETIME NOT NULL,
                                       revogado TINYINT NOT NULL DEFAULT 0,
                                       criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                                       FOREIGN KEY (usuario_id) REFERENCES usuario(id) ON DELETE CASCADE
);

ALTER TABLE cargo
    ADD CONSTRAINT fk_cargo_usuario
        FOREIGN KEY (criado_por) REFERENCES usuario(id);

-- =========================================================
-- CLIENTE
-- =========================================================

CREATE TABLE cliente (
                         id BIGINT AUTO_INCREMENT PRIMARY KEY,
                         nome_razao_social VARCHAR(150) NOT NULL,
                         cpf_cnpj VARCHAR(14) UNIQUE,
                         is_pf TINYINT NOT NULL,
                         rg VARCHAR(15),
                         status_cliente_id INT NOT NULL,
                         como_conheceu ENUM('INSTAGRAM', 'SITE', 'INDICACAO', 'OUTROS') NOT NULL,
                         endereco_id BIGINT,
                         data_hora_envio_formulario DATETIME,
                         data_hora_transformacao_em_cliente DATETIME,

                         FOREIGN KEY (status_cliente_id) REFERENCES status_cliente(id),
                         FOREIGN KEY (endereco_id) REFERENCES endereco(id)
);

CREATE TABLE contato (
                         id BIGINT AUTO_INCREMENT PRIMARY KEY,
                         nome VARCHAR(150) NOT NULL,
                         email VARCHAR(255) NOT NULL,
                         telefone VARCHAR(20) NOT NULL,
                         profissao VARCHAR(100),
                         cliente_id BIGINT NOT NULL,
                         principal TINYINT DEFAULT 0,

                         FOREIGN KEY (cliente_id) REFERENCES cliente(id)
);

ALTER TABLE padrao_caminho_armazenamento
    ADD CONSTRAINT fk_padrao_caminho_cliente
        FOREIGN KEY (cliente_id) REFERENCES cliente(id);

-- =========================================================
-- PROCESSO API (ALTERADO CONFORME DER)
-- =========================================================

CREATE TABLE processo_dados_api (
                                    id BIGINT AUTO_INCREMENT PRIMARY KEY,
                                    numero_cnj VARCHAR(25) UNIQUE,
                                    tribunal_tramitacao VARCHAR(200),
                                    instancia VARCHAR(200),
                                    data_ajuizamento DATETIME,
                                    nivel_sigilo VARCHAR(50),
                                    classe_processual VARCHAR(255),
                                    formato VARCHAR(100),
                                    sistema_tribunal VARCHAR(200),
                                    orgao_julgador VARCHAR(255),
                                    assunto VARCHAR(255)
);

-- =========================================================
-- MOVIMENTAÇÃO OFICIAL
-- =========================================================

CREATE TABLE movimentacoes_oficiais (
                                        id BIGINT AUTO_INCREMENT PRIMARY KEY,
                                        codigo VARCHAR(20),
                                        descricao TEXT,
                                        data_hora_movimentacao DATETIME,
                                        processo_dados_api_id BIGINT,

                                        FOREIGN KEY (processo_dados_api_id)
                                            REFERENCES processo_dados_api(id)
);

-- =========================================================
-- DOCUMENTO
-- =========================================================

CREATE TABLE documento (
                           id BIGINT AUTO_INCREMENT PRIMARY KEY,
                           criado_por_usuario_id BIGINT NOT NULL,
                           tipo_documento_id INT NOT NULL,
                           padrao_caminho_armazenamento_id BIGINT,

                           nome_original VARCHAR(255) NOT NULL,
                           mime_type VARCHAR(100),
                           tamanho_bytes BIGINT,
                           hash_arquivo CHAR(64),

                           onedrive_drive_id VARCHAR(100),
                           onedrive_item_id VARCHAR(200),
                           onedrive_web_url VARCHAR(1024),
                           onedrive_url_thumbnail TEXT,
                           onedrive_url_download TEXT,

                           data_hora_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                           ultima_atualizacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                           ativo TINYINT DEFAULT 1,
                           inativado_em DATETIME,
                           inativado_por_usuario_id BIGINT,

                           FOREIGN KEY (criado_por_usuario_id)
                               REFERENCES usuario(id),

                           FOREIGN KEY (tipo_documento_id)
                               REFERENCES tipo_documento(id),

                           FOREIGN KEY (padrao_caminho_armazenamento_id)
                               REFERENCES padrao_caminho_armazenamento(id),

                           FOREIGN KEY (inativado_por_usuario_id)
                               REFERENCES usuario(id)
);

-- =========================================================
-- PROCESSO APLICAÇÃO (ALTERADO CONFORME DER)
-- =========================================================


CREATE TABLE processo_dados_aplicacao (
                                          id BIGINT AUTO_INCREMENT PRIMARY KEY,

                                          usuario_responsavel_id BIGINT,
                                          cliente_id BIGINT NOT NULL,

                                          descricao_caso TEXT,
                                          observacao TEXT,

                                          prioridade_id INT,
                                          fase_processo_id INT,

                                          ultima_atualizacao DATETIME,
                                          data_hora_inicio DATETIME,

                                          status ENUM('ATIVO', 'SUSPENSO', 'ENCERRADO', 'SOLICITACAO', 'NEGADO') NOT NULL DEFAULT 'ATIVO',

                                          data_audiencia DATETIME,

                                          encerrado_suspenso_em              DATETIME,
                                          encerrado_suspenso_por_usuario_id  BIGINT,

                                          motivo_status_processo_id          INT,
                                          justificativa_status               TEXT,

                                          sigla_tribunal_id INT,

                                          valor_causa DECIMAL(15,2),
                                          cnpj_informado_formulario VARCHAR(14),

                                          processo_dados_api_id BIGINT,

                                          FOREIGN KEY (usuario_responsavel_id)
                                              REFERENCES usuario(id),

                                          FOREIGN KEY (cliente_id)
                                              REFERENCES cliente(id),

                                          FOREIGN KEY (prioridade_id)
                                              REFERENCES prioridade(id),

                                          FOREIGN KEY (fase_processo_id)
                                              REFERENCES fase_processo(id),

                                          FOREIGN KEY (encerrado_suspenso_por_usuario_id)
                                              REFERENCES usuario(id),

                                          FOREIGN KEY (motivo_status_processo_id)
                                              REFERENCES motivo_status_processo(id),

                                          FOREIGN KEY (sigla_tribunal_id)
                                              REFERENCES sigla_tribunal(id),

                                          FOREIGN KEY (processo_dados_api_id)
                                              REFERENCES processo_dados_api(id)
);

-- =========================================================
-- PROCESSO DOCUMENTO
-- =========================================================

CREATE TABLE processo_documento (
                                    documento_id BIGINT,
                                    processo_dados_aplicacao_id BIGINT,
                                    anexado_por_usuario_id BIGINT,
                                    anexado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                                    PRIMARY KEY (documento_id, processo_dados_aplicacao_id),

                                    FOREIGN KEY (documento_id)
                                        REFERENCES documento(id),

                                    FOREIGN KEY (processo_dados_aplicacao_id)
                                        REFERENCES processo_dados_aplicacao(id),

                                    FOREIGN KEY (anexado_por_usuario_id)
                                        REFERENCES usuario(id)
);

-- =========================================================
-- HISTÓRICO PROCESSO
-- =========================================================

CREATE TABLE historico_processo (
                                    id BIGINT AUTO_INCREMENT PRIMARY KEY,

                                    processo_dados_aplicacao_id BIGINT NOT NULL,
                                    usuario_id BIGINT NOT NULL,

                                    descricao_alteracao TEXT,

                                    data_hora_alteracao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                                    tipo_alteracao_id INT NOT NULL,

                                    fase_anterior_id INT,
                                    fase_nova_id INT,

                                    FOREIGN KEY (processo_dados_aplicacao_id)
                                        REFERENCES processo_dados_aplicacao(id),

                                    FOREIGN KEY (usuario_id)
                                        REFERENCES usuario(id),

                                    FOREIGN KEY (tipo_alteracao_id)
                                        REFERENCES tipo_alteracao(id),

                                    FOREIGN KEY (fase_anterior_id)
                                        REFERENCES fase_processo(id),

                                    FOREIGN KEY (fase_nova_id)
                                        REFERENCES fase_processo(id)
);

-- =========================================================
-- CARGO PERMISSÃO
-- =========================================================

CREATE TABLE cargo_permissao (
                                 cargo_id INT,
                                 permissao_id INT,
                                 atribuido_por BIGINT,
                                 data_hora_atribuicao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                                 PRIMARY KEY (cargo_id, permissao_id),

                                 FOREIGN KEY (cargo_id)
                                     REFERENCES cargo(id),

                                 FOREIGN KEY (permissao_id)
                                     REFERENCES permissao(id),

                                 FOREIGN KEY (atribuido_por)
                                     REFERENCES usuario(id)
);

-- =========================================================
-- OTP
-- =========================================================

CREATE TABLE usuario_otp (
                             email VARCHAR(255) PRIMARY KEY,
                             otp VARCHAR(60) NOT NULL,
                             expira_em DATETIME NOT NULL,
                             tentativas INT NOT NULL DEFAULT 0,
                             usuario_valido TINYINT NOT NULL DEFAULT 0
) ENGINE=MEMORY;

-- =========================================================
-- SHEDLOCK (CONTROLE DE LOCK DISTRIBUÍDO DE AGENDADORES)
-- =========================================================

CREATE TABLE shedlock (
                          name VARCHAR(64) NOT NULL,
                          lock_until TIMESTAMP(3) NOT NULL,
                          locked_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
                          locked_by VARCHAR(255) NOT NULL,
                          PRIMARY KEY (name)
);

-- =========================================================
-- INDEXES
-- =========================================================

CREATE INDEX idx_usuario_cargo_id
    ON usuario(cargo_id);

CREATE INDEX idx_usuario_ativo
    ON usuario(ativo);

CREATE INDEX idx_cliente_status
    ON cliente(status_cliente_id);

CREATE INDEX idx_cliente_endereco
    ON cliente(endereco_id);

CREATE INDEX idx_cliente_cpf_cnpj
    ON cliente(cpf_cnpj);

CREATE INDEX idx_processo_api_numero_cnj
    ON processo_dados_api(numero_cnj);

CREATE INDEX idx_movimentacao_processo
    ON movimentacoes_oficiais(processo_dados_api_id);

CREATE INDEX idx_processo_app_usuario
    ON processo_dados_aplicacao(usuario_responsavel_id);

CREATE INDEX idx_processo_app_cliente
    ON processo_dados_aplicacao(cliente_id);

CREATE INDEX idx_processo_app_fase
    ON processo_dados_aplicacao(fase_processo_id);

CREATE INDEX idx_processo_app_api
    ON processo_dados_aplicacao(processo_dados_api_id);

CREATE INDEX idx_processo_app_status
    ON processo_dados_aplicacao(status);

-- =========================================================
-- INSERTS BASE
-- =========================================================

INSERT INTO cargo (id, nome)
VALUES (1, 'ADMIN'),
       (2, 'Sem Cargo');

INSERT INTO usuario (nome, email, senha, cargo_id)
VALUES (
           'SISTEMA SGPJ',
           'sistema.sgpj@gmail.com',
           NULL,
           1
       ),
       (
           'Thauany Bezerra',
           'thauany@gmail.com',
           '$2a$12$AD1HxQJj.U.dQaam6fntBOCko5p6vrk/6bLLsv79EgpqzqFt7I5D6',
           1
       );

INSERT INTO permissao (nome) VALUES
                                 ('CRIAR PROCESSO'),
                                 ('EDITAR PROCESSO'),
                                 ('EXCLUIR PROCESSO'),
                                 ('ACEITAR SOLICITAÇÃO'),
                                 ('NEGAR SOLICITAÇÃO'),
                                 ('CRIAR CLIENTE'),
                                 ('EDITAR CLIENTE'),
                                 ('EXCLUIR CLIENTE'),
                                 ('CRIAR CARGO'),
                                 ('EDITAR CARGO'),
                                 ('EXCLUIR CARGO'),
                                 ('CRIAR USUÁRIO'),
                                 ('EDITAR USUÁRIO'),
                                 ('EXCLUIR USUÁRIO'),
                                 ('CRIAR DOCUMENTO'),
                                 ('EDITAR DOCUMENTO'),
                                 ('EXCLUIR DOCUMENTO'),
                                 ('TODAS AS PERMISSÕES'),
                                 ('SEM PERMISSÕES');

INSERT INTO cargo_permissao (cargo_id, permissao_id)
VALUES (1, 18),
       (2, 19);

INSERT INTO status_cliente (nome) VALUES
                                      ('LEAD'),
                                      ('INATIVO'),
                                      ('ATIVO');

INSERT INTO fase_processo (nome) VALUES
                                     ('INICIAL'),
                                     ('EMENDA A INCIAL'),
                                     ('CITAÇÃO'),
                                     ('DEFESA'),
                                     ('SANEAMENTO'),
                                     ('JULGAMENTO'),
                                     ('SENTENÇA'),
                                     ('CUPRIMENTO DE SENTENÇA'),
                                     ('PENHORA'),
                                     ('ACORDO'),
                                     ('SUSPENSO');

INSERT INTO sigla_tribunal (sigla_tribunal) VALUES
                                                ('TJAC'),
                                                ('TJAL'),
                                                ('TJAP'),
                                                ('TJAM'),
                                                ('TJBA'),
                                                ('TJCE'),
                                                ('TJDF'),
                                                ('TJES'),
                                                ('TJGO'),
                                                ('TJMA'),
                                                ('TJMT'),
                                                ('TJMS'),
                                                ('TJMG'),
                                                ('TJPA'),
                                                ('TJPB'),
                                                ('TJPR'),
                                                ('TJPE'),
                                                ('TJPI'),
                                                ('TJRJ'),
                                                ('TJRN'),
                                                ('TJRS'),
                                                ('TJRO'),
                                                ('TJRR'),
                                                ('TJSC'),
                                                ('TJSE'),
                                                ('TJSP'),
                                                ('TJTO');

INSERT INTO prioridade (nome) VALUES
                                  ('ALTA'),
                                  ('MEDIA'),
                                  ('BAIXA');

INSERT INTO tipo_documento (nome) VALUES
                                      ('RG'),
                                      ('DOCUMENTO DE DEFESA'),
                                      ('COMPROVANTE DE ENDEREÇO'),
                                      ('CTPS'),
                                      ('PROCURAÇÃO'),
                                      ('OUTROS');

INSERT INTO tipo_alteracao (nome) VALUES
                                      ('ABERTURA DE PROCESSO'),
                                      ('FECHAMENTO DE PROCESSO'),
                                      ('MUDANÇA DE STATUS'),
                                      ('ADIÇÃO DE DOCUMENTO'),
                                      ('ADIÇÃO DE ARQUIVO'),
                                      ('OBSERVAÇÃO'),
                                      ('ATUALIZAÇÃO DE DADOS'),
                                      ('ALTERAÇÃO DE RESPONSÁVEL'),
                                      ('AUDIÊNCIA');

INSERT INTO motivo_status_processo (nome, aplicavel_a) VALUES
                                                           ('ACORDO',                  'ENCERRADO'),
                                                           ('SEM RESOLUÇÃO DO MÉRITO', 'ENCERRADO'),
                                                           ('PENHORA TOTAL',           'ENCERRADO'),
                                                           ('PAGAMENTO VOLUNTÁRIO',    'ENCERRADO'),
                                                           ('ACORDO PARCELADO',        'SUSPENSO'),
                                                           ('TRATATIVAS',              'SUSPENSO'),
                                                           ('AUSÊNCIA DE BENS',        'SUSPENSO'),
                                                           ('DETERMINAÇÃO JUDICIAL',   'SUSPENSO'),
                                                           ('OUTROS',                  'AMBOS');

INSERT INTO cliente (nome_razao_social, cpf_cnpj, is_pf, status_cliente_id, data_hora_transformacao_em_cliente) VALUES
  ('Maria Fernanda Souza',     '98765432100',     1, 3, NOW()),
  ('Construtora Omega LTDA',   '12345678000195',  0, 3, NOW()),
  ('Pedro Augusto Lima',       '11122233344',     1, 3, NOW()),
  ('Tech Solutions S/A',       '98765432000111',   0, 3, NOW()),
  ('Ana Paula Rodrigues',      '55566677788',     1, 3, NOW()),
  ('Logística Rápida ME',      '11223344000155',   0, 3, NOW()),
  ('Carlos Eduardo Martins',   '33344455566',     1, 3, NOW()),
  ('Indústria Nova LTDA',      '22334455000177',   0, 3, NOW()),
  ('Beatriz Santos Ferreira',  '77788899900',     1, 3, NOW()),
  ('Roberto Carvalho Nunes',   '44455566677',     1, 3, NOW());	

-- ============================================================
-- 2. PROCESSO_DADOS_API
-- (Nao preenchido previamente - os dados oficiais serao consultados e persistidos sob demanda via API)
-- ============================================================

-- ============================================================
-- 3. PROCESSOS (40 registros de exemplo)
-- ============================================================
INSERT INTO processo_dados_aplicacao (
  usuario_responsavel_id,
  cliente_id,
  descricao_caso,
  observacao,
  prioridade_id,
  fase_processo_id,
  ultima_atualizacao,
  data_hora_inicio,
  status,
  data_audiencia,
  encerrado_suspenso_em,
  encerrado_suspenso_por_usuario_id,
  motivo_status_processo_id,
  justificativa_status,
  sigla_tribunal_id,
  valor_causa,
  processo_dados_api_id
) VALUES
  -- Lote 1 (1 a 10)
  (1, 1, 'Acao de cobranca de divida bancaria com clausulas abusivas.', 'Cliente solicitou prioridade na analise pericial dos juros.', 1, 1, '2025-06-01 14:20:00', '2025-01-10 14:20:00', 'ATIVO', '2025-08-15 14:00:00', NULL, NULL, NULL, NULL, 1, 15000.00, NULL),
  (1, 2, 'Rescisao contratual trabalhista com pedido de verbas rescisorias.', 'Aguardando envio dos termos de homologacao pelo cliente.', 2, 3, '2025-06-02 14:20:00', '2025-02-15 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 19, 28000.00, NULL),
  (1, 3, 'Apelacao em danos morais contra fornecedora de energia.', 'Sentenca favoravel confirmada em segunda instancia.', 1, 7, '2025-06-03 14:20:00', '2024-11-20 14:20:00', 'ENCERRADO', NULL, '2025-06-03 14:20:00', 1, 1, 'Homologado acordo judicial e quitacao integral da obrigacao.', 13, 45000.00, NULL),
  (1, 4, 'Execucao de titulo extrajudicial contra devedor inadimplente.', 'Tentativa de citacao e penhora de ativos financeiros.', 3, 4, '2025-06-04 14:20:00', '2025-03-05 14:20:00', 'ATIVO', '2025-09-10 09:00:00', NULL, NULL, NULL, NULL, 16, 8000.00, NULL),
  (1, 5, 'Acao de alimentos para menor incapaz apos separacao conjugal.', 'Fixados alimentos provisorios em favor do menor.', 1, 5, '2025-06-05 14:20:00', '2025-04-01 14:20:00', 'ATIVO', '2025-07-20 10:30:00', NULL, NULL, NULL, NULL, 21, 3500.00, NULL),
  (1, 1, 'Acao indenizatoria por acidente de trabalho com sequelas.', 'Processo suspenso por acordo de parcelamento da indenizacao.', 2, 11, '2025-06-06 14:20:00', '2025-01-25 14:20:00', 'SUSPENSO', NULL, '2025-06-06 14:20:00', 1, 5, 'Suspensao deferida para adimplemento de parcelas convencionadas.', 1, 120000.00, NULL),
  (1, 2, 'Acao possessoria de reintegracao de imovel comercial invadido.', 'Mandado liminar de reintegracao deferido pelo magistrado.', 3, 3, '2025-06-07 14:20:00', '2024-12-10 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 13, 55000.00, NULL),
  (1, 3, 'Agravo de instrumento para tutela de urgencia bancaria.', 'Cumprimento voluntario integral do valor condenatorio.', 1, 7, '2025-06-08 14:20:00', '2025-02-28 14:20:00', 'ENCERRADO', NULL, '2025-06-08 14:20:00', 1, 4, 'Deposito judicial voluntario realizado pela instituicao financeira.', 19, 30000.00, NULL),
  (1, 4, 'Acao declaratoria de nulidade de clausula contratual.', 'Contestacao protocolada pela parte re dentro do prazo legal.', 2, 1, '2025-06-09 14:20:00', '2025-03-18 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 16, 22000.00, NULL),
  (1, 5, 'Acao de despejo por falta de pagamento de aluguel.', 'Audiencia de conciliacao designada com o locatario.', 3, 4, '2025-06-10 14:20:00', '2025-05-02 14:20:00', 'ATIVO', '2025-08-28 11:00:00', NULL, NULL, NULL, NULL, 1, 18000.00, NULL),

  -- Lote 2 (11 a 20)
  (1, 6, 'Acao civil publica por dano ambiental de empresa de mineracao.', 'Pericia ambiental tecnica em andamento para apuracao.', 1, 1, '2025-06-11 14:20:00', '2024-10-15 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 2, 500000.00, NULL),
  (1, 7, 'Acao de cobranca por inadimplemento de servicos de frete.', 'Suspensao processual acordada para tratativas extrajudiciais.', 2, 11, '2025-06-12 14:20:00', '2025-01-30 14:20:00', 'SUSPENSO', NULL, '2025-06-12 14:20:00', 1, 6, 'Partes em tratativas para formulacao de composicao amigavel.', 4, 12000.00, NULL),
  (1, 1, 'Recurso inominado em acao consumerista de plano de saude.', 'Processo extinto sem resolucao de merito por perda de objeto.', 3, 7, '2025-06-13 14:20:00', '2024-09-05 14:20:00', 'ENCERRADO', NULL, '2025-06-13 14:20:00', 1, 2, 'Extincao processual sem resolucao de merito nos termos do art. 485 CPC.', 1, 9500.00, NULL),
  (1, 8, 'Acao trabalhista por horas extras nao pagas ao longo de 3 anos.', 'Instrucao probatoria agendada perante a vara trabalhista.', 1, 7, '2025-06-14 14:20:00', '2025-04-10 14:20:00', 'ATIVO', '2025-09-02 08:30:00', NULL, NULL, NULL, NULL, 13, 35000.00, NULL),
  (1, 9, 'Acao de divorcio litigioso com disputas por guarda e bens.', 'Requerida expedicao de oficios para localizacao de contas bancarias.', 2, 4, '2025-06-15 14:20:00', '2025-02-20 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 21, 80000.00, NULL),
  (1, 10, 'Acao revisional de financiamento com taxas abusivas.', 'Fase executiva de restituicao de valores cobrados indevidamente.', 3, 9, '2025-06-16 14:20:00', '2025-05-01 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 16, 62000.00, NULL),
  (1, 1, 'Acao de inventario e partilha de bens de espolio litigioso.', 'Suspensao determinada pelo juizo ate desfecho de acao de filiacao.', 1, 11, '2025-06-17 14:20:00', '2025-03-22 14:20:00', 'SUSPENSO', NULL, '2025-06-17 14:20:00', 1, 8, 'Determinacao judicial de sobrestamento do feito por prejudicialidade externa.', 1, 250000.00, NULL),
  (1, 2, 'Acao trabalhista por falta de deposito de FGTS.', 'Apresentada contestacao refutando alegacoes da inicial.', 2, 1, '2025-06-18 14:20:00', '2024-11-11 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 19, 42000.00, NULL),
  (1, 3, 'Acao monitoria baseada em cheque sem fundo.', 'Apresentacao de embargos monitorios pelo devedor.', 3, 5, '2025-06-19 14:20:00', '2025-01-08 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 13, 7500.00, NULL),
  (1, 4, 'Acao de usucapiao extraordinaria de imovel rural.', 'Sentenca de procedencia transitada em julgado e registro deferido.', 1, 7, '2025-06-20 14:20:00', '2025-02-14 14:20:00', 'ENCERRADO', NULL, '2025-06-20 14:20:00', 1, 9, 'Sentenca declaratoria de usucapiao definitiva e encerramento dos autos.', 2, 180000.00, NULL),

  -- Lote 3 (21 a 30)
  (1, 5, 'Acao de cobranca por servicos de TI prestados e nao pagos.', 'Audiencia de conciliacao designada perante a vara civel.', 2, 4, '2025-06-21 14:20:00', '2025-04-25 14:20:00', 'ATIVO', '2025-08-20 09:30:00', NULL, NULL, NULL, NULL, 1, 95000.00, NULL),
  (1, 6, 'Embargos de declaracao para sanar omissao em acordao.', 'Embargos acolhidos para integracao do julgado colegiado.', 3, 3, '2025-06-22 14:20:00', '2025-03-10 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 16, 5000.00, NULL),
  (1, 7, 'Acao indenizatoria por acidente em transporte de carga.', 'Suspensao por inexistencia de bens penhoraveis via Sisbajud.', 1, 11, '2025-06-23 14:20:00', '2025-01-17 14:20:00', 'SUSPENSO', NULL, '2025-06-23 14:20:00', 1, 7, 'Sobrestamento fundamentado no art. 921, III do CPC por ausencia de bens.', 21, 200000.00, NULL),
  (1, 8, 'Acao de alimentos para filho maior estudante universitario.', 'Designada audiencia conciliatoria entre as partes litigantes.', 2, 1, '2025-06-24 14:20:00', '2024-12-20 14:20:00', 'ATIVO', '2025-09-25 10:00:00', NULL, NULL, NULL, NULL, 13, 4500.00, NULL),
  (1, 9, 'Acao possessoria para protecao de area industrial ocupada.', 'Acordo celebrado com desocupacao espontanea da area.', 3, 7, '2025-06-25 14:20:00', '2025-05-12 14:20:00', 'ENCERRADO', NULL, '2025-06-25 14:20:00', 1, 1, 'Homologacao de termo de acordo e entrega voluntaria das chaves.', 19, 135000.00, NULL),
  (1, 1, 'Acao trabalhista por verbas rescisorias com assedio moral.', 'Aguardando pericia psicologica do reclamante.', 1, 7, '2025-06-26 14:20:00', '2025-04-03 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 1, 65000.00, NULL),
  (1, 2, 'Acao civil por obrigacao de fazer: entrega de imovel.', 'Audiencia preliminar conciliatoria marcada em juizo.', 2, 4, '2025-06-27 14:20:00', '2025-02-07 14:20:00', 'ATIVO', '2025-07-30 15:30:00', NULL, NULL, NULL, NULL, 4, 290000.00, NULL),
  (1, 10, 'Apelacao civel sobre propriedade de terreno rural.', 'Penhora total de bens com satisfacao do credito exequendo.', 3, 7, '2025-06-28 14:20:00', '2025-01-22 14:20:00', 'ENCERRADO', NULL, '2025-06-28 14:20:00', 1, 3, 'Extincao da fase executiva em razao da penhora e adjudicacao total dos bens.', 2, 160000.00, NULL),
  (1, 4, 'Acao declaratoria para dissolucao de sociedade empresarial.', 'Apresentacao de laudo preliminar contabil e balanco patrimonial.', 1, 1, '2025-06-29 14:20:00', '2025-03-30 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 16, 480000.00, NULL),
  (1, 5, 'Acao de despejo por descumprimento de locacao comercial.', 'Sobrestamento deferido pelo magistrado para negociacao direta.', 2, 11, '2025-06-30 14:20:00', '2025-05-05 14:20:00', 'SUSPENSO', NULL, '2025-06-30 14:20:00', 1, 6, 'Suspensao requerida em conjunto para elaboracao de aditivo de locacao.', 13, 75000.00, NULL),

  -- Lote 4 (31 a 40)
  (1, 1, 'Execucao fiscal de debito tributario municipal por IPTU.', 'Audiencia conciliatoria designada para negociacao fiscal.', 3, 9, '2025-07-01 14:20:00', '2024-08-15 14:20:00', 'ATIVO', '2025-11-12 09:00:00', NULL, NULL, NULL, NULL, 1, 22000.00, NULL),
  (1, 6, 'Acao de cobranca por cheque devolvido sem provisao.', 'Analise de impugnacao aos calculos apresentados.', 1, 5, '2025-07-02 14:20:00', '2025-04-18 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 21, 17500.00, NULL),
  (1, 7, 'Acao indenizatoria por acidente de transito com lesao.', 'Quitacao integral comprovada e extincao do processo homologada.', 2, 7, '2025-07-03 14:20:00', '2025-02-05 14:20:00', 'ENCERRADO', NULL, '2025-07-03 14:20:00', 1, 4, 'Pagamento voluntario comprovado nos autos com expedicao de alvara.', 19, 85000.00, NULL),
  (1, 8, 'Agravo regimental por cerceamento de defesa.', 'Suspensao por determinacao judicial aguardando julgamento de tema repetitivo.', 3, 11, '2025-07-04 14:20:00', '2024-10-30 14:20:00', 'SUSPENSO', NULL, '2025-07-04 14:20:00', 1, 8, 'Determinacao judicial de sobrestamento vinculada a tese em recurso repetitivo.', 13, 34000.00, NULL),
  (1, 9, 'Acao trabalhista por adicional de insalubridade fabril.', 'Audiencia de instrucao designada perante a vara do trabalho.', 1, 1, '2025-07-05 14:20:00', '2025-03-14 14:20:00', 'ATIVO', '2025-10-01 14:30:00', NULL, NULL, NULL, NULL, 2, 28500.00, NULL),
  (1, 10, 'Acao revisional de financiamento imobiliario.', 'Manifestacao quanto aos calculos de amortizacao apresentados pelo banco.', 2, 3, '2025-07-06 14:20:00', '2025-05-20 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 1, 110000.00, NULL),
  (1, 1, 'Acao de alimentos gravidicos para protecao da gestante.', 'Acordo integral homologado em juizo para prestar alimentos.', 3, 7, '2025-07-07 14:20:00', '2024-09-18 14:20:00', 'ENCERRADO', NULL, '2025-07-07 14:20:00', 1, 1, 'Acordo homologado com fixacao consensual da pensao alimenticia.', 16, 2800.00, NULL),
  (1, 2, 'Acao monitoria baseada em nota promissoria com avalista.', 'Designada audiencia de conciliacao e saneamento do feito.', 1, 9, '2025-07-08 14:20:00', '2025-01-05 14:20:00', 'ATIVO', '2025-08-05 10:00:00', NULL, NULL, NULL, NULL, 21, 48000.00, NULL),
  (1, 3, 'Acao civil publica por violacao de direitos do consumidor.', 'Citacao regular das partes e aguardo de manifestacoes contestatorias.', 2, 1, '2025-07-09 14:20:00', '2025-04-22 14:20:00', 'ATIVO', NULL, NULL, NULL, NULL, NULL, 4, 320000.00, NULL),
  (1, 4, 'Acao de inventario com divergencia sobre partilha.', 'Suspensao decretada por ausencia temporaria de bens desimpedidos.', 3, 11, '2025-07-10 14:20:00', '2025-05-08 14:20:00', 'SUSPENSO', NULL, '2025-07-10 14:20:00', 1, 7, 'Suspensao autorizada para regularizacao e desembargo dos imoveis arrolados.', 13, 195000.00, NULL);

INSERT INTO microsoft_token_config (refresh_token)
VALUES ('M.C534_BAY.0.U.-Cl8qkU0yAnKgN9ume1Oa32br06eN8h6MuC6zgquEpDXcFiVp9w6df69A4y2uDm07WuC0B0eqo!j9CQxp0nf8rUMFoYlTsyXBlKUsrlN093ce9iJgMjM7!wzaEAfp4FNW5rahu0*dkMe5ybaxeZbAtSfTVS5J!BEclKY37GXC0TJk38B52VcCgP!MvchDJx27vfaJy*pigBryrBzT13mG!o71z9alxqYy*boGc1*aELl4zft1rmO6d5fdFgsm4r5a*OMU42hXVF707G77mqScmAHYTr0oS5oDg4I1Lf8h7LCbNs5ZUf!ClyxIHPCiWvn6mbxE2wknchWZOoLp4mFoXgqlBLLJSt8Tz*9msq1HB6!fAbdDIZTYByA*9J!6soIRfiC0ZtZxAR347m!RXoinluiZWAdejXjao6aReGLcqbZR');

CREATE USER IF NOT EXISTS 'app_sgpj'@'%' IDENTIFIED BY '1234';
GRANT SELECT, INSERT, UPDATE, DELETE ON sgpj.* TO 'app_sgpj'@'%';
FLUSH PRIVILEGES;
-- =========================================================
-- TABELA DE CONTROLE DE LOCK DISTRIBUIDO (SHEDLOCK)
-- Necessaria para tarefas agendadas do Spring Boot em cluster
-- =========================================================
CREATE TABLE IF NOT EXISTS shedlock (
    name VARCHAR(64) NOT NULL,
    lock_until TIMESTAMP(3) NOT NULL,
    locked_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    locked_by VARCHAR(255) NOT NULL,
    PRIMARY KEY (name)
);
