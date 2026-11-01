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
                                      ('ALTERAÇÃO DE RESPONSÁVEL');

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
-- 2. PROCESSO_DADOS_API (40 em 4 lotes de 10)
-- ============================================================
INSERT INTO processo_dados_api (numero_cnj, tribunal_tramitacao, instancia, data_ajuizamento, nivel_sigilo, classe_processual, formato, sistema_tribunal, orgao_julgador, assunto) VALUES
  ('00010001120250000001', 'TJSP', '1a Instancia', '2025-01-10', 'Publico', 'Acao Civil', 'Eletronico', 'ESAJ', '1a Vara Civel de SP', 'Cobranca'),
  ('00020002220250000002', 'TJRJ', '1a Instancia', '2025-02-15', 'Publico', 'Acao Trabalhista', 'Eletronico', 'PROJUDI', '2a Vara do Trabalho', 'Rescisao'),
  ('00030003320250000003', 'TJMG', '2a Instancia', '2024-11-20', 'Publico', 'Apelacao', 'Fisico', 'SISCOM', 'Camara Civel', 'Danos Morais'),
  ('00040004420250000004', 'TJPR', '1a Instancia', '2025-03-05', 'Publico', 'Acao Executiva', 'Eletronico', 'PROJUDI', '3a Vara Civel', 'Execucao de Titulo'),
  ('00050005520250000005', 'TJRS', '1a Instancia', '2025-04-01', 'Publico', 'Acao de Alimentos', 'Eletronico', 'THEMIS', '1a Vara de Familia', 'Alimentos'),
  ('00060006620250000006', 'TJSP', '1a Instancia', '2025-01-25', 'Publico', 'Acao Indenizatoria', 'Eletronico', 'ESAJ', '5a Vara Civel de SP', 'Indenizacao'),
  ('00070007720250000007', 'TJMG', '1a Instancia', '2024-12-10', 'Publico', 'Acao Possessoria', 'Fisico', 'SISCOM', '2a Vara Civel', 'Reintegracao de Posse'),
  ('00080008820250000008', 'TJRJ', '2a Instancia', '2025-02-28', 'Publico', 'Agravo de Instrumento', 'Eletronico', 'PROJUDI', 'Camara Civel', 'Tutela de Urgencia'),
  ('00090009920250000009', 'TJPR', '1a Instancia', '2025-03-18', 'Publico', 'Acao Declaratoria', 'Eletronico', 'PROJUDI', '1a Vara Empresarial', 'Contrato'),
  ('00100010020250000010', 'TJSP', '1a Instancia', '2025-05-02', 'Publico', 'Acao de Despejo', 'Eletronico', 'ESAJ', '4a Vara Civel de SP', 'Locacao');

INSERT INTO processo_dados_api (numero_cnj, tribunal_tramitacao, instancia, data_ajuizamento, nivel_sigilo, classe_processual, formato, sistema_tribunal, orgao_julgador, assunto) VALUES
  ('00110011120250000011', 'TJAL', '1a Instancia', '2024-10-15', 'Publico', 'Acao Civil Publica', 'Eletronico', 'ESAJ', '1a Vara Publica', 'Dano Ambiental'),
  ('00120012220250000012', 'TJAM', '1a Instancia', '2025-01-30', 'Publico', 'Acao de Cobranca', 'Fisico', 'THEMIS', '3a Vara Civel', 'Divida'),
  ('00130013320250000013', 'TJSP', '2a Instancia', '2024-09-05', 'Publico', 'Recurso Inominado', 'Eletronico', 'ESAJ', 'Camara Especial', 'Consumidor'),
  ('00140014420250000014', 'TJMG', '1a Instancia', '2025-04-10', 'Publico', 'Acao Trabalhista', 'Eletronico', 'SISCOM', '5a Vara do Trabalho', 'Horas Extras'),
  ('00150015520250000015', 'TJRS', '1a Instancia', '2025-02-20', 'Publico', 'Acao de Divorcio', 'Fisico', 'THEMIS', '2a Vara de Familia', 'Divorcio'),
  ('00160016620250000016', 'TJPR', '1a Instancia', '2025-05-01', 'Publico', 'Acao Revisional', 'Eletronico', 'PROJUDI', '2a Vara Bancaria', 'Revisao Contratual'),
  ('00170017720250000017', 'TJSP', '1a Instancia', '2025-03-22', 'Publico', 'Acao de Inventario', 'Eletronico', 'ESAJ', '3a Vara de Sucessoes', 'Inventario'),
  ('00180018820250000018', 'TJRJ', '1a Instancia', '2024-11-11', 'Publico', 'Acao Trabalhista', 'Fisico', 'PROJUDI', '7a Vara do Trabalho', 'FGTS'),
  ('00190019920250000019', 'TJMG', '1a Instancia', '2025-01-08', 'Publico', 'Acao Monitoria', 'Eletronico', 'SISCOM', '4a Vara Civel', 'Monitoria'),
  ('00200020020250000020', 'TJAL', '1a Instancia', '2025-02-14', 'Publico', 'Acao de Usucapiao', 'Fisico', 'ESAJ', '1a Vara de Registros', 'Usucapiao');

INSERT INTO processo_dados_api (numero_cnj, tribunal_tramitacao, instancia, data_ajuizamento, nivel_sigilo, classe_processual, formato, sistema_tribunal, orgao_julgador, assunto) VALUES
  ('00210021120250000021', 'TJSP', '1a Instancia', '2025-04-25', 'Publico', 'Acao de Cobranca', 'Eletronico', 'ESAJ', '6a Vara Civel de SP', 'Cobranca'),
  ('00220022220250000022', 'TJPR', '2a Instancia', '2025-03-10', 'Publico', 'Embargos de Declaracao', 'Eletronico', 'PROJUDI', 'Camara Civel', 'Omissao'),
  ('00230023320250000023', 'TJRS', '1a Instancia', '2025-01-17', 'Publico', 'Acao Indenizatoria', 'Fisico', 'THEMIS', '3a Vara Civel', 'Acidente'),
  ('00240024420250000024', 'TJMG', '1a Instancia', '2024-12-20', 'Publico', 'Acao de Alimentos', 'Eletronico', 'SISCOM', '1a Vara de Familia', 'Alimentos'),
  ('00250025520250000025', 'TJRJ', '1a Instancia', '2025-05-12', 'Publico', 'Acao Possessoria', 'Eletronico', 'PROJUDI', '2a Vara Civel', 'Posse'),
  ('00260026620250000026', 'TJSP', '1a Instancia', '2025-04-03', 'Publico', 'Acao Trabalhista', 'Eletronico', 'ESAJ', '8a Vara do Trabalho', 'Verbas Rescisorias'),
  ('00270027720250000027', 'TJAM', '1a Instancia', '2025-02-07', 'Publico', 'Acao Civil', 'Fisico', 'THEMIS', '2a Vara Civel', 'Obrigacao de Fazer'),
  ('00280028820250000028', 'TJAL', '2a Instancia', '2025-01-22', 'Publico', 'Apelacao', 'Eletronico', 'ESAJ', 'Camara Civel', 'Propriedade'),
  ('00290029920250000029', 'TJPR', '1a Instancia', '2025-03-30', 'Publico', 'Acao Declaratoria', 'Eletronico', 'PROJUDI', '4a Vara Empresarial', 'Dissolucao Societaria'),
  ('00300030020250000030', 'TJMG', '1a Instancia', '2025-05-05', 'Publico', 'Acao de Despejo', 'Fisico', 'SISCOM', '3a Vara Locaticia', 'Locacao Comercial');

INSERT INTO processo_dados_api (numero_cnj, tribunal_tramitacao, instancia, data_ajuizamento, nivel_sigilo, classe_processual, formato, sistema_tribunal, orgao_julgador, assunto) VALUES
  ('10108901220228260292', 'TJSP', '1a Instancia', '2024-08-15', 'Publico', 'Acao Executiva', 'Eletronico', 'ESAJ', '2a Vara de Execucoes', 'Execucao Fiscal'),
  ('00017707620248260005', 'TJSP', '1a Instancia', '2025-04-18', 'Publico', 'Acao de Cobranca', 'Eletronico', 'THEMIS', '4a Vara Civel', 'Cheque'),
  ('00340034420250000033', 'TJSP', '1a Instancia', '2025-02-05', 'Publico', 'Acao Indenizatoria', 'Fisico', 'PROJUDI', '5a Vara Civel', 'Acidente de Transito'),
  ('00340034420250000034', 'TJSP', '2a Instancia', '2024-10-30', 'Publico', 'Agravo Regimental', 'Eletronico', 'SISCOM', 'Camara Civel', 'Recurso'),
  ('00350035520250000035', 'TJSP', '1a Instancia', '2025-03-14', 'Publico', 'Acao Trabalhista', 'Eletronico', 'ESAJ', '2a Vara do Trabalho', 'Adicional Insalubridade'),
  ('00360036620250000036', 'TJSP', '1a Instancia', '2025-05-20', 'Publico', 'Acao Revisional', 'Eletronico', 'ESAJ', '7a Vara Civel de SP', 'Juros Abusivos'),
  ('00370037720250000037', 'TJSP', '1a Instancia', '2024-09-18', 'Publico', 'Acao de Alimentos', 'Fisico', 'PROJUDI', '3a Vara de Familia', 'Alimentos Gravidicos'),
  ('00380038820250000038', 'TJSP', '1a Instancia', '2025-01-05', 'Publico', 'Acao Monitoria', 'Eletronico', 'THEMIS', '5a Vara Civel', 'Nota Promissoria'),
  ('00390039920250000039', 'TJSP', '1a Instancia', '2025-04-22', 'Publico', 'Acao Civil Publica', 'Eletronico', 'THEMIS', '1a Vara Publica', 'Direitos do Consumidor'),
  ('00400040020250000040', 'TJSP', '1a Instancia', '2025-05-08', 'Publico', 'Acao de Inventario', 'Fisico', 'SISCOM', '2a Vara de Sucessoes', 'Partilha');

-- ============================================================
-- 3. PROCESSOS (40 em 4 lotes de 10)
-- ============================================================
INSERT INTO processo_dados_aplicacao (usuario_responsavel_id, cliente_id, descricao_caso, prioridade_id, fase_processo_id, ultima_atualizacao, data_hora_inicio, status, data_audiencia, sigla_tribunal_id, valor_causa, processo_dados_api_id) VALUES
  (1, 1, 'Acao de cobranca de divida bancaria com clausulas abusivas.', 1, 1, '2025-06-01 14:20:00', '2025-01-10 14:20:00', 'ATIVO', '2025-08-15 14:00:00', 1, 15000.00, 1),
  (1, 2, 'Rescisao contratual trabalhista com pedido de verbas rescisorias.', 2, 3, '2025-06-02 14:20:00', '2025-02-15 14:20:00', 'ATIVO', NULL, 19, 28000.00, 2),
  (1, 3, 'Apelacao em danos morais contra fornecedora de energia.', 1, 7, '2025-06-03 14:20:00', '2024-11-20 14:20:00', 'ENCERRADO', NULL, 13, 45000.00, 3),
  (1, 4, 'Execucao de titulo extrajudicial contra devedor inadimplente.', 3, 4, '2025-06-04 14:20:00', '2025-03-05 14:20:00', 'ATIVO', '2025-09-10 09:00:00', 16, 8000.00, 4),
  (1, 5, 'Acao de alimentos para menor incapaz apos separacao conjugal.', 1, 5, '2025-06-05 14:20:00', '2025-04-01 14:20:00', 'ATIVO', '2025-07-20 10:30:00', 21, 3500.00, 5),
  (1, 1, 'Acao indenizatoria por acidente de trabalho com sequelas.', 2, 9, '2025-06-06 14:20:00', '2025-01-25 14:20:00', 'SUSPENSO', NULL, 1, 120000.00, 6),
  (1, 2, 'Acao possessoria de reintegracao de imovel comercial invadido.', 3, 3, '2025-06-07 14:20:00', '2024-12-10 14:20:00', 'ATIVO', NULL, 13, 55000.00, 7),
  (1, 3, 'Agravo de instrumento para tutela de urgencia bancaria.', 1, 10, '2025-06-08 14:20:00', '2025-02-28 14:20:00', 'ENCERRADO', '2025-10-05 15:00:00', 19, 30000.00, 8),
  (1, 4, 'Acao declaratoria de nulidade de clausula contratual.', 2, 1, '2025-06-09 14:20:00', '2025-03-18 14:20:00', 'ATIVO', NULL, 16, 22000.00, 9),
  (1, 5, 'Acao de despejo por falta de pagamento de aluguel.', 3, 4, '2025-06-10 14:20:00', '2025-05-02 14:20:00', 'ATIVO', '2025-08-28 11:00:00', 1, 18000.00, 10);

INSERT INTO processo_dados_aplicacao (usuario_responsavel_id, cliente_id, descricao_caso, prioridade_id, fase_processo_id, ultima_atualizacao, data_hora_inicio, status, data_audiencia, sigla_tribunal_id, valor_causa, processo_dados_api_id) VALUES
  (1, 6, 'Acao civil publica por dano ambiental de empresa de mineracao.', 1, 1, '2025-06-11 14:20:00', '2024-10-15 14:20:00', 'ATIVO', NULL, 2, 500000.00, 11),
  (1, 7, 'Acao de cobranca por inadimplemento de servicos de frete.', 2, 3, '2025-06-12 14:20:00', '2025-01-30 14:20:00', 'SUSPENSO', NULL, 4, 12000.00, 12),
  (1, 1, 'Recurso inominado em acao consumerista de plano de saude.', 3, 5, '2025-06-13 14:20:00', '2024-09-05 14:20:00', 'ENCERRADO', NULL, 1, 9500.00, 13),
  (1, 8, 'Acao trabalhista por horas extras nao pagas ao longo de 3 anos.', 1, 7, '2025-06-14 14:20:00', '2025-04-10 14:20:00', 'ATIVO', '2025-09-02 08:30:00', 13, 35000.00, 14),
  (1, 9, 'Acao de divorcio litigioso com disputas por guarda e bens.', 2, 4, '2025-06-15 14:20:00', '2025-02-20 14:20:00', 'ATIVO', NULL, 21, 80000.00, 15),
  (1, 10, 'Acao revisional de financiamento com taxas abusivas.', 3, 9, '2025-06-16 14:20:00', '2025-05-01 14:20:00', 'ATIVO', NULL, 16, 62000.00, 16),
  (1, 1, 'Acao de inventario e partilha de bens de espolio litigioso.', 1, 3, '2025-06-17 14:20:00', '2025-03-22 14:20:00', 'SUSPENSO', '2025-10-15 14:00:00', 1, 250000.00, 17),
  (1, 2, 'Acao trabalhista por falta de deposito de FGTS.', 2, 1, '2025-06-18 14:20:00', '2024-11-11 14:20:00', 'ATIVO', NULL, 19, 42000.00, 18),
  (1, 3, 'Acao monitoria baseada em cheque sem fundo.', 3, 5, '2025-06-19', '2025-01-08', 'ATIVO', NULL, 13, 7500.00, 19),
  (1, 4, 'Acao de usucapiao extraordinaria de imovel rural.', 1, 7, '2025-06-20', '2025-02-14', 'ENCERRADO', NULL, 2, 180000.00, 20);

INSERT INTO processo_dados_aplicacao (usuario_responsavel_id, cliente_id, descricao_caso, prioridade_id, fase_processo_id, ultima_atualizacao, data_hora_inicio, status, data_audiencia, sigla_tribunal_id, valor_causa, processo_dados_api_id) VALUES
  (1, 5, 'Acao de cobranca por servicos de TI prestados e nao pagos.', 2, 4, '2025-06-21 14:20:00', '2025-04-25 14:20:00', 'ATIVO', '2025-08-20 09:30:00', 1, 95000.00, 21),
  (1, 6, 'Embargos de declaracao para sanar omissao em acordao.', 3, 3, '2025-06-22 14:20:00', '2025-03-10 14:20:00', 'ATIVO', NULL, 16, 5000.00, 22),
  (1, 7, 'Acao indenizatoria por acidente em transporte de carga.', 1, 9, '2025-06-23 14:20:00', '2025-01-17 14:20:00', 'SUSPENSO', NULL, 21, 200000.00, 23),
  (1, 8, 'Acao de alimentos para filho maior estudante universitario.', 2, 1, '2025-06-24 14:20:00', '2024-12-20 14:20:00', 'ATIVO', '2025-09-25 10:00:00', 13, 4500.00, 24),
  (1, 9, 'Acao possessoria para protecao de area industrial ocupada.', 3, 5, '2025-06-25 14:20:00', '2025-05-12 14:20:00', 'ENCERRADO', NULL, 19, 135000.00, 25),
  (1, 1, 'Acao trabalhista por verbas rescisorias com assedio moral.', 1, 7, '2025-06-26 14:20:00', '2025-04-03 14:20:00', 'ATIVO', NULL, 1, 65000.00, 26),
  (1, 2, 'Acao civil por obrigacao de fazer: entrega de imovel.', 2, 4, '2025-06-27 14:20:00', '2025-02-07 14:20:00', 'ATIVO', '2025-07-30 15:30:00', 4, 290000.00, 27),
  (1, 10, 'Apelacao civel sobre propriedade de terreno rural.', 3, 10, '2025-06-28 14:20:00', '2025-01-22 14:20:00', 'ENCERRADO', NULL, 2, 160000.00, 28),
  (1, 4, 'Acao declaratoria para dissolucao de sociedade empresarial.', 1, 1, '2025-06-29', '2025-03-30', 'ATIVO', NULL, 16, 480000.00, 29),
  (1, 5, 'Acao de despejo por descumprimento de locacao comercial.', 2, 3, '2025-06-30', '2025-05-05', 'SUSPENSO', NULL, 13, 75000.00, 30);

INSERT INTO processo_dados_aplicacao (usuario_responsavel_id, cliente_id, descricao_caso, prioridade_id, fase_processo_id, ultima_atualizacao, data_hora_inicio, status, data_audiencia, sigla_tribunal_id, valor_causa, processo_dados_api_id) VALUES
  (1, 1, 'Execucao fiscal de debito tributario municipal por IPTU.', 3, 9, '2025-07-01', '2024-08-15', 'ATIVO', '2025-11-12 09:00:00', 1, 22000.00, 31),
  (1, 6, 'Acao de cobranca por cheque devolvido sem provisao.', 1, 5, '2025-07-02', '2025-04-18', 'ATIVO', NULL, 21, 17500.00, 32),
  (1, 7, 'Acao indenizatoria por acidente de transito com lesao.', 2, 7, '2025-07-03', '2025-02-05', 'ENCERRADO', NULL, 19, 85000.00, 33),
  (1, 8, 'Agravo regimental por cerceamento de defesa.', 3, 4, '2025-07-04', '2024-10-30', 'SUSPENSO', NULL, 13, 34000.00, 34),
  (1, 9, 'Acao trabalhista por adicional de insalubridade fabril.', 1, 1, '2025-07-05', '2025-03-14', 'ATIVO', '2025-10-01 14:30:00', 2, 28500.00, 35),
  (1, 10, 'Acao revisional de financiamento imobiliario.', 2, 3, '2025-07-06', '2025-05-20', 'ATIVO', NULL, 1, 110000.00, 36),
  (1, 1, 'Acao de alimentos gravidicos para protecao da gestante.', 3, 5, '2025-07-07', '2024-09-18', 'ENCERRADO', NULL, 16, 2800.00, 37),
  (1, 2, 'Acao monitoria baseada em nota promissoria com avalista.', 1, 9, '2025-07-08', '2025-01-05', 'ATIVO', '2025-08-05 10:00:00', 21, 48000.00, 38),
  (1, 3, 'Acao civil publica por violacao de direitos do consumidor.', 2, 1, '2025-07-09', '2025-04-22', 'ATIVO', NULL, 4, 320000.00, 39),
  (1, 4, 'Acao de inventario com divergencia sobre partilha.', 3, 4, '2025-07-10', '2025-05-08', 'SUSPENSO', NULL, 13, 195000.00, 40);


INSERT INTO microsoft_token_config (refresh_token)
VALUES ('');

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
