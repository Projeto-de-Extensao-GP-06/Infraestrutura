SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;
DROP DATABASE IF EXISTS sgpj;
CREATE DATABASE sgpj CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
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


INSERT INTO endereco (
    cep,
    logradouro,
    numero,
    bairro,
    cidade,
    estado,
    complemento
)
VALUES (
    '01311-000',
    'Rua Haddock Lobo',
    '850',
    'Cerqueira César',
    'São Paulo',
    'SP',
    'Conjunto 1204'
);

INSERT INTO cliente (
    nome_razao_social,
    cpf_cnpj,
    is_pf,
    rg,
    status_cliente_id,
    como_conheceu,
    endereco_id,
    data_hora_envio_formulario,
    data_hora_transformacao_em_cliente
)
VALUES (
    'Tech Solutions Sistemas LTDA',
    '12345678000195',
    0,
    NULL,
    (SELECT id FROM status_cliente WHERE nome = 'ATIVO'),
    'indicacao',
    (
        SELECT id
        FROM endereco
        WHERE cep = '01311-000'
          AND logradouro = 'Rua Haddock Lobo'
          AND numero = '850'
    ),
    NOW(),
    NOW()
);

INSERT INTO contato (
    nome,
    email,
    telefone,
    profissao,
    cliente_id,
    principal
)
VALUES (
    'Rafael Almeida Costa',
    'rafael@techsolutions.com.br',
    '11977776666',
    'Diretor',
    (
        SELECT id
        FROM cliente
        WHERE cpf_cnpj = '12345678000195'
    ),
    1
);


-- =========================================================
-- PROCESSO 5 - TECH SOLUTIONS SISTEMAS LTDA (PJ)
-- =========================================================

INSERT INTO processo_dados_api (numero_cnj
)
VALUES (
    '10108901220228260292'
);

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
    sigla_tribunal_id,
    valor_causa,
    processo_dados_api_id
)
VALUES (
    (
        SELECT id
        FROM usuario
        WHERE email = 'thauany@gmail.com'
    ),
    (
        SELECT id
        FROM cliente
        WHERE cpf_cnpj = '12345678000195'
    ),
    'Execução de título extrajudicial decorrente de contrato empresarial.',
    'Aguardando pagamento voluntário.',
    (
        SELECT id
        FROM prioridade
        WHERE nome = 'ALTA'
    ),
    (
        SELECT id
        FROM fase_processo
        WHERE nome = 'PENHORA'
    ),
    NOW(),
    '2026-05-18 16:10:00',
    'ATIVO',
    (
        SELECT id
        FROM sigla_tribunal
        WHERE sigla_tribunal = 'TJSP'
    ),
    150000.00,
    (
        SELECT id
        FROM processo_dados_api
        WHERE numero_cnj = '10108901220228260292'
    )
);

INSERT INTO microsoft_token_config (refresh_token)
VALUES ('M.C534_BAY.0.U.-Cl8qkU0yAnKgN9ume1Oa32br06eN8h6MuC6zgquEpDXcFiVp9w6df69A4y2uDm07WuC0B0eqo!j9CQxp0nf8rUMFoYlTsyXBlKUsrlN093ce9iJgMjM7!wzaEAfp4FNW5rahu0*dkMe5ybaxeZbAtSfTVS5J!BEclKY37GXC0TJk38B52VcCgP!MvchDJx27vfaJy*pigBryrBzT13mG!o71z9alxqYy*boGc1*aELl4zft1rmO6d5fdFgsm4r5a*OMU42hXVF707G77mqScmAHYTr0oS5oDg4I1Lf8h7LCbNs5ZUf!ClyxIHPCiWvn6mbxE2wknchWZOoLp4mFoXgqlBLLJSt8Tz*9msq1HB6!fAbdDIZTYByA*9J!6soIRfiC0ZtZxAR347m!RXoinluiZWAdejXjao6aReGLcqbZR');

CREATE USER IF NOT EXISTS 'app_sgpj'@'%' IDENTIFIED BY '1234';
GRANT SELECT, INSERT, UPDATE, DELETE ON sgpj.* TO 'app_sgpj'@'%';
FLUSH PRIVILEGES;

use sgpj;

select * from processo_dados_api;
select * from processo_dados_aplicacao;
select * from sigla_tribunal;
select * from padrao_caminho_armazenamento;
select * from processo_dados_aplicacao where id = 3;
select * from usuario where id = 1;
