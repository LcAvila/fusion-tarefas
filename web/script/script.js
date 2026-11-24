(function () {
    "use strict";

    var CONTEXT_PATH = window.FUSION_TAREFAS_CONTEXT_PATH || "";
    CONTEXT_PATH = CONTEXT_PATH.replace(/\/$/, "");

    var ENDPOINT_NOTIFICACAO =
        CONTEXT_PATH + "/custom/task-notification";

    var linhaSelecionada = null;
    var temporizadorResultado = null;
    var temporizadorDesvanecer = null;
    var notificacaoEmAndamento = false;
    var estadoOrdenacao = {
        coluna: null,
        direcao: "asc"
    };

    function mostrarResultado(mensagem, tipo, manterVisivel) {
        var resultado = document.getElementById("resultadoNotificacao");
        if (!resultado) return;

        clearTimeout(temporizadorResultado);
        clearTimeout(temporizadorDesvanecer);

        resultado.textContent = mensagem;
        resultado.classList.remove(
            "error",
            "resultado-sucesso",
            "resultado-erro",
            "is-visible",
            "is-hiding"
        );
        resultado.classList.add(
            tipo === "erro" ? "resultado-erro" : "resultado-sucesso",
            "is-visible"
        );
        resultado.style.display = "block";
        resultado.style.visibility = "visible";
        resultado.style.opacity = "1";

        if (manterVisivel === true) return;

        temporizadorResultado = setTimeout(function () {
            resultado.classList.add("is-hiding");
            resultado.style.opacity = "0";

            temporizadorDesvanecer = setTimeout(function () {
                resultado.style.display = "none";
                resultado.style.visibility = "hidden";
                resultado.style.opacity = "";
                resultado.textContent = "";
                resultado.classList.remove(
                    "is-visible",
                    "is-hiding",
                    "resultado-sucesso",
                    "resultado-erro"
                );
            }, 300);
        }, 4000);
    }

    function selecionarLinha(linha) {
        if (!linha) return;

        if (linhaSelecionada && linhaSelecionada !== linha) {
            linhaSelecionada.classList.remove("selected");
        }

        linhaSelecionada = linha;
        linha.classList.add("selected");
    }

    function obterLinhasSelecionadas() {
        var linhas = [];

        document.querySelectorAll(
            "#tabelaTarefas tbody tr"
        ).forEach(function (linha) {
            var checkbox = linha.querySelector(".row-select");
            if (checkbox && checkbox.checked) {
                linhas.push(linha);
            }
        });

        return linhas;
    }

    function atualizarSelecao() {
        var selecionadas = obterLinhasSelecionadas();
        var info = document.getElementById("selecionadosInfo");
        var todos = document.querySelectorAll(
            "#tabelaTarefas tbody .row-select"
        );
        var selecionarTodos = document.getElementById(
            "selecionarTodos"
        );

        if (info) {
            info.textContent = selecionadas.length
                + " selecionada(s)";
        }

        if (selecionarTodos) {
            selecionarTodos.checked = todos.length > 0
                && selecionadas.length === todos.length;
            selecionarTodos.indeterminate = selecionadas.length > 0
                && selecionadas.length < todos.length;
        }
    }

    function alternarTodos(campo) {
        document.querySelectorAll(
            "#tabelaTarefas tbody .row-select"
        ).forEach(function (checkbox) {
            checkbox.checked = campo.checked;
        });

        atualizarSelecao();
    }

    function obterItemDaLinha(linha) {
        return {
            taskInstanceId: linha.dataset.taskInstanceId || "",
            activityId: linha.dataset.activityId || "",
            taskId: linha.dataset.taskId || "",
            email: linha.dataset.email || "",
            responsavel: linha.dataset.responsavel || "",
            responsavelId: linha.dataset.responsavelId || "",
            processo: linha.dataset.processo || "",
            tarefa: linha.dataset.tarefa || "",
            protocolo: linha.dataset.protocolo || "",
            vencimento: linha.dataset.vencimento || "",
            diasAtraso: linha.dataset.diasAtraso || ""
        };
    }

function construirUrlTarefa(taskInstanceId) {
    var parametrosTarefa = new URLSearchParams({
        type: "Task",
        showSummaryBtn: "true",
        take: "false",
        taskInstanceId: taskInstanceId,
        edit: "true",
        readOnly: "false",
        boxname: "user_active_tasks",
        showTaskCloseBtn: "true",
        forcedBreadcrumb: "true",
        from: "3",
        fromemail: "true",
        setCurrentSideBar: "true"
    });

    var linkInterno = "portal/render/Task?"
        + parametrosTarefa.toString();

    var parametrosRedirecionamento = new URLSearchParams({
        link: linkInterno
    });

    return window.location.origin
        + CONTEXT_PATH
        + "/rest/redirect/mail/link?"
        + parametrosRedirecionamento.toString();
}

    function abrirTarefa(linha) {
        var taskInstanceId =
            linha.dataset.taskInstanceId || "";

        if (!taskInstanceId) {
            mostrarResultado(
                "Esta tarefa não possui taskInstanceId.",
                "erro"
            );
            return;
        }

        window.open(
            construirUrlTarefa(taskInstanceId),
            "_blank"
        );
    }

    async function enviarNotificacaoUnica(item) {
        if (!item.taskInstanceId) {
            throw new Error(
                "Tarefa sem taskInstanceId. Não é possível notificar."
            );
        }

        var parametros = new URLSearchParams();
        parametros.append("taskInstanceId", item.taskInstanceId);

        var resposta;

        try {
            resposta = await fetch(ENDPOINT_NOTIFICACAO, {
                method: "POST",
                headers: {
                    Accept: "application/json",
                    "X-Requested-With": "XMLHttpRequest"
                },
                credentials: "same-origin",
                body: parametros
            });
        } catch (erro) {
            throw new Error(
                "Não foi possível conectar ao servidor de notificação. "
                + erro.message
            );
        }

        var texto = await resposta.text();
        var resultado;

        try {
            resultado = JSON.parse(texto);
        } catch (erro) {
            throw new Error(
                "Resposta inválida do servidor (HTTP "
                + resposta.status + "): "
                + texto.replace(/\s+/g, " ").substring(0, 300)
            );
        }

        var sucesso = resultado.success === true
            || resultado.sucesso === true;

        if (!resposta.ok || !sucesso) {
            throw new Error(
                resultado.message
                || resultado.mensagem
                || "Não foi possível enviar a notificação."
            );
        }

        return resultado;
    }

    async function notificarItens(itens) {
        var sucesso = 0;
        var falhas = [];

        for (var i = 0; i < itens.length; i++) {
            try {
                await enviarNotificacaoUnica(itens[i]);
                sucesso++;
            } catch (erro) {
                falhas.push(
                    (itens[i].protocolo
                        || itens[i].taskInstanceId
                        || "tarefa")
                    + ": " + erro.message
                );
            }
        }

        if (falhas.length === 0) {
            mostrarResultado(
                "Notificação enviada com sucesso para "
                + sucesso + " tarefa(s).",
                "sucesso"
            );
        } else if (sucesso > 0) {
            mostrarResultado(
                sucesso + " notificação(ões) enviada(s). "
                + falhas.length + " falharam:\n"
                + falhas.join("\n"),
                "erro"
            );
        } else {
            mostrarResultado(
                "Erro ao enviar:\n" + falhas.join("\n"),
                "erro"
            );
        }
    }

    async function notificarSelecionados() {
        if (notificacaoEmAndamento) return;

        var linhas = obterLinhasSelecionadas();

        if (linhas.length === 0) {
            mostrarResultado(
                "Selecione pelo menos uma tarefa.",
                "erro"
            );
            return;
        }

        notificacaoEmAndamento = true;
        mostrarResultado(
            "Enviando notificações...",
            "sucesso",
            true
        );

        try {
            await notificarItens(linhas.map(obterItemDaLinha));
        } finally {
            notificacaoEmAndamento = false;
        }
    }

    async function notificarLinha(linha) {
        if (notificacaoEmAndamento) return;

        selecionarLinha(linha);
        notificacaoEmAndamento = true;
        mostrarResultado(
            "Enviando notificação...",
            "sucesso",
            true
        );

        try {
            await notificarItens([obterItemDaLinha(linha)]);
        } finally {
            notificacaoEmAndamento = false;
        }
    }

    function setTexto(id, valor) {
        var elemento = document.getElementById(id);
        if (elemento) {
            elemento.textContent = valor;
        }
    }

    function preencherDetalhes(linha) {
        setTexto("detProcesso", linha.dataset.processo || "-");
        setTexto("detSolicitante", linha.dataset.solicitante || "-");
        setTexto("detProtocolo", linha.dataset.protocolo || "-");
        setTexto("detTarefa", linha.dataset.tarefa || "-");
        setTexto(
            "detResponsavel",
            linha.dataset.responsavel || "Não atribuído"
        );
        setTexto(
            "detDataSolicitacao",
            linha.dataset.dataSolicitacao || "-"
        );
        setTexto("detVencimento", linha.dataset.vencimento || "-");
        setTexto(
            "detDiasAtraso",
            (linha.dataset.diasAtraso || "-") + " dia(s)"
        );
        setTexto(
            "detEmail",
            linha.dataset.email || "Não informado"
        );
        setTexto(
            "detDescricao",
            linha.dataset.descricao || "Sem descrição"
        );
    }

    function abrirDetalhes(linha) {
        selecionarLinha(linha);
        preencherDetalhes(linha);

        var modal = document.getElementById("modalDetalhes");
        if (modal) {
            modal.classList.add("open");
        }
    }

    function fecharDetalhes() {
        var modal = document.getElementById("modalDetalhes");
        if (modal) {
            modal.classList.remove("open");
        }
    }

    function alternarFiltros() {
        var corpo = document.getElementById("corpoFiltros");
        var botao = document.getElementById("toggleFiltros");

        if (!corpo || !botao) return;

        var vaiAbrir = corpo.hasAttribute("hidden");

        if (vaiAbrir) {
            corpo.removeAttribute("hidden");
        } else {
            corpo.setAttribute("hidden", "hidden");
        }

        corpo.setAttribute(
            "aria-hidden",
            String(!vaiAbrir)
        );
        botao.setAttribute(
            "aria-expanded",
            String(vaiAbrir)
        );
        botao.setAttribute(
            "aria-label",
            vaiAbrir ? "Esconder filtros" : "Mostrar filtros"
        );
        botao.setAttribute(
            "title",
            vaiAbrir ? "Esconder filtros" : "Mostrar filtros"
        );
        botao.classList.toggle("is-open", vaiAbrir);
    }

    function iniciarAtualizacao() {
        var botao = document.getElementById("btnAtualizarLista");

        if (!botao || botao.classList.contains("is-refreshing")) {
            return;
        }

        botao.classList.add("is-refreshing");
        botao.disabled = true;

        window.setTimeout(function () {
            window.location.reload();
        }, 700);
    }

    function valorCelula(linha, indice) {
        var celula = linha.cells[indice];
        if (!celula) return "";

        return (
            celula.getAttribute("data-sort-value")
            || celula.textContent
        ).replace(/\s+/g, " ").trim();
    }

    function valorNumero(valor) {
        var numero = Number.parseFloat(
            String(valor || "")
                .replace(/[^0-9,-]/g, "")
                .replace(",", ".")
        );

        return Number.isNaN(numero) ? 0 : numero;
    }

    function valorData(valor) {
        var partes = String(valor || "").trim().split(" ");
        var data = (partes[0] || "").split("-");
        var hora = (partes[1] || "00:00:00").split(":");

        if (data.length !== 3) return 0;

        var timestamp = new Date(
            Number(data[0]),
            Number(data[1]) - 1,
            Number(data[2]),
            Number(hora[0] || 0),
            Number(hora[1] || 0),
            Number(hora[2] || 0)
        ).getTime();

        return Number.isNaN(timestamp) ? 0 : timestamp;
    }

    function comparar(a, b, tipo) {
        if (tipo === "number") {
            return valorNumero(a) - valorNumero(b);
        }

        if (tipo === "date") {
            return valorData(a) - valorData(b);
        }

        return String(a).normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLocaleLowerCase("pt-BR")
            .localeCompare(
                String(b).normalize("NFD")
                    .replace(/[\u0300-\u036f]/g, "")
                    .toLocaleLowerCase("pt-BR"),
                "pt-BR",
                {
                    numeric: true,
                    sensitivity: "base"
                }
            );
    }

    function ordenarTabela(indice, cabecalho) {
        var tabela = document.getElementById("tabelaTarefas");
        var corpo = tabela && tabela.querySelector("tbody");

        if (!tabela || !corpo) return;

        var tipo = cabecalho.dataset.sort || "text";
        var direcao = estadoOrdenacao.coluna === indice
            && estadoOrdenacao.direcao === "asc"
            ? "desc"
            : "asc";

        estadoOrdenacao.coluna = indice;
        estadoOrdenacao.direcao = direcao;

        tabela.querySelectorAll("th.sortable").forEach(
            function (th) {
                th.classList.remove("sort-asc", "sort-desc");

                var indicador = th.querySelector(".sort-indicator");
                if (indicador) {
                    indicador.textContent = "";
                }
            }
        );

        cabecalho.classList.add(
            direcao === "asc" ? "sort-asc" : "sort-desc"
        );

        var indicadorAtual = cabecalho.querySelector(
            ".sort-indicator"
        );

        if (indicadorAtual) {
            indicadorAtual.textContent = direcao === "asc"
                ? "▲"
                : "▼";
        }

        var linhas = Array.prototype.slice.call(
            corpo.querySelectorAll("tr")
        );

        linhas.sort(function (linhaA, linhaB) {
            var resultado = comparar(
                valorCelula(linhaA, indice),
                valorCelula(linhaB, indice),
                tipo
            );

            return direcao === "asc" ? resultado : -resultado;
        });

        linhas.forEach(function (linha) {
            corpo.appendChild(linha);
        });
    }

    function configurarOrdenacao() {
        var tabela = document.getElementById("tabelaTarefas");
        if (!tabela) return;

        tabela.querySelectorAll("thead th").forEach(
            function (cabecalho, indice) {
                if (indice === 0 || indice === 8) return;

                cabecalho.classList.add("sortable");
                cabecalho.dataset.sort = indice === 7
                    ? "number"
                    : indice === 6 ? "date" : "text";
                cabecalho.setAttribute(
                    "title",
                    "Clique para ordenar"
                );

                if (!cabecalho.querySelector(".sort-indicator")) {
                    var indicador = document.createElement("span");
                    indicador.className = "sort-indicator";
                    cabecalho.appendChild(indicador);
                }

                cabecalho.addEventListener("click", function () {
                    ordenarTabela(indice, cabecalho);
                });
            }
        );
    }

    function inicializarEventosLinhas() {
        document.querySelectorAll(
            "#tabelaTarefas tbody tr"
        ).forEach(function (linha) {
            linha.addEventListener("click", function (event) {
                if (
                    event.target.closest(".row-select")
                    || event.target.closest(".actions")
                ) {
                    return;
                }

                selecionarLinha(linha);
            });

            var detalhar = linha.querySelector(
                '[data-acao="detalhar"]'
            );
            var verTarefa = linha.querySelector(
                '[data-acao="ver-tarefa"]'
            );
            var notificar = linha.querySelector(
                '[data-acao="notificar"]'
            );
            var checkbox = linha.querySelector(".row-select");

            if (detalhar) {
                detalhar.addEventListener("click", function (event) {
                    event.stopPropagation();
                    abrirDetalhes(linha);
                });
            }

            if (verTarefa) {
                verTarefa.addEventListener("click", function (event) {
                    event.stopPropagation();
                    abrirTarefa(linha);
                });
            }

            if (notificar) {
                notificar.addEventListener("click", function (event) {
                    event.stopPropagation();
                    notificarLinha(linha);
                });
            }

            if (checkbox) {
                checkbox.addEventListener("click", function (event) {
                    event.stopPropagation();
                });
                checkbox.addEventListener("change", atualizarSelecao);
            }
        });
    }

    function inicializar() {
        var selecionarTodos = document.getElementById(
            "selecionarTodos"
        );
        var botaoSelecionadas = document.getElementById(
            "btnNotificarSelecionadas"
        );
        var toggleFiltros = document.getElementById(
            "toggleFiltros"
        );
        var btnAtualizarLista = document.getElementById(
            "btnAtualizarLista"
        );
        var fechar = document.getElementById("btnFecharModal");
        var fecharRodape = document.getElementById(
            "btnFecharModalRodape"
        );
        var verTarefaModal = document.getElementById(
            "btnVerTarefaModal"
        );
        var notificarModal = document.getElementById(
            "btnNotificarModal"
        );
        var modal = document.getElementById("modalDetalhes");

        if (selecionarTodos) {
            selecionarTodos.addEventListener("change", function () {
                alternarTodos(selecionarTodos);
            });
        }

        if (botaoSelecionadas) {
            botaoSelecionadas.addEventListener(
                "click",
                notificarSelecionados
            );
        }

        if (toggleFiltros) {
            toggleFiltros.addEventListener(
                "click",
                alternarFiltros
            );
        }

        if (btnAtualizarLista) {
            btnAtualizarLista.addEventListener(
                "click",
                iniciarAtualizacao
            );
        }

        if (fechar) {
            fechar.addEventListener("click", fecharDetalhes);
        }

        if (fecharRodape) {
            fecharRodape.addEventListener(
                "click",
                fecharDetalhes
            );
        }

        if (verTarefaModal) {
            verTarefaModal.addEventListener("click", function () {
                if (linhaSelecionada) {
                    abrirTarefa(linhaSelecionada);
                }
            });
        }

        if (notificarModal) {
            notificarModal.addEventListener("click", function () {
                if (!linhaSelecionada) {
                    mostrarResultado(
                        "Nenhuma tarefa foi selecionada.",
                        "erro"
                    );
                    return;
                }

                notificarLinha(linhaSelecionada);
            });
        }

        if (modal) {
            modal.addEventListener("click", function (event) {
                if (event.target === modal) {
                    fecharDetalhes();
                }
            });
        }

        document.addEventListener("keydown", function (event) {
            if (event.key === "Escape") {
                fecharDetalhes();
            }
        });

        inicializarEventosLinhas();
        configurarOrdenacao();
        atualizarSelecao();
    }

    if (document.readyState === "loading") {
        document.addEventListener(
            "DOMContentLoaded",
            inicializar
        );
    } else {
        inicializar();
    }
})();
