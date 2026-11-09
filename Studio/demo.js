(function () {
  "use strict";

  var connection = document.getElementById("connection-state");
  var sdkSummary = document.getElementById("sdk-summary");
  var toolSummary = document.getElementById("tool-summary");
  var sdkRoot = document.getElementById("sdk-root");
  var moduleRoot = document.getElementById("module-root");
  var settingsPanel = document.getElementById("settings-panel");
  var customProject = document.getElementById("custom-project");
  var projectSelect = document.getElementById("project-select");
  var projectHelp = document.getElementById("project-help");
  var buildButton = document.getElementById("build-button");
  var buildLog = document.getElementById("build-log");
  var jobState = document.getElementById("job-state");
  var jobDetail = document.getElementById("job-detail");
  var activeJob = null;
  var pollTimer = null;
  var lastLog = "";

  function updateBuildAvailability() {
    buildButton.disabled = Boolean(activeJob) ||
      (!customProject.value.trim() && (projectSelect.disabled || !projectSelect.value));
  }

  function request(url, options) {
    return fetch(url, options).then(function (response) {
      return response.text().then(function (text) {
        var body;
        try {
          body = JSON.parse(text);
        } catch (error) {
          throw new Error("Respuesta no válida del servicio local (HTTP " + response.status + ").");
        }
        if (!response.ok) throw new Error(body.error || "La solicitud no se pudo completar.");
        return body;
      });
    });
  }

  function setConnection(ready, text) {
    connection.classList.toggle("is-offline", !ready);
    connection.querySelector("span:last-child").textContent = text;
  }

  function setToolStatus(name, ready, value) {
    var status = document.getElementById("status-" + name);
    var item = status.parentElement;
    status.textContent = value;
    item.classList.toggle("is-ready", ready);
    item.classList.toggle("is-missing", !ready);
  }

  function setJobState(state, label) {
    jobState.className = "job-state state-" + state;
    jobState.querySelector("span").textContent = "";
    jobState.lastChild.textContent = " " + label;
  }

  function showMessage(message, isError) {
    buildLog.replaceChildren();
    var line = document.createElement("p");
    line.className = isError ? "log-line-error" : "";
    line.textContent = message;
    buildLog.appendChild(line);
    lastLog = message;
  }

  function displayLogs(lines) {
    var content = lines.join("\n");
    if (content === lastLog) return;
    var nearBottom = buildLog.scrollHeight - buildLog.scrollTop - buildLog.clientHeight < 48;
    buildLog.replaceChildren();
    if (!lines.length) {
      var empty = document.createElement("p");
      empty.className = "log-placeholder";
      empty.textContent = "Preparando el proceso de compilación…";
      buildLog.appendChild(empty);
    } else {
      lines.forEach(function (text) {
        var line = document.createElement("p");
        line.textContent = text;
        if (/error|failed|exception|no se pudo/i.test(text)) line.className = "log-line-error";
        if (/build succeeded|package written|files written|compiled .*\.o/i.test(text)) line.className = "log-line-success";
        buildLog.appendChild(line);
      });
    }
    lastLog = content;
    if (nearBottom) buildLog.scrollTop = buildLog.scrollHeight;
  }

  function loadProjects() {
    return request("/api/projects").then(function (data) {
      projectSelect.replaceChildren();
      if (!data.projects.length) {
        var empty = document.createElement("option");
        empty.value = "";
        empty.textContent = "No se encontraron proyectos de aplicación";
        projectSelect.appendChild(empty);
        projectHelp.textContent = "Comprueba la ruta del SDK y que contiene muestras SharpProspero de aplicaciones.";
        updateBuildAvailability();
        return;
      }

      data.projects.forEach(function (project) {
        var option = document.createElement("option");
        option.value = project.id;
        option.textContent = project.name;
        projectSelect.appendChild(option);
      });
      projectSelect.disabled = false;
      projectHelp.textContent = data.projects.length + " proyectos de aplicación encontrados en samples.";
      var preferred = data.projects.find(function (project) { return project.id === "prospero-arcade/Arcade.csproj"; });
      if (preferred) projectSelect.value = preferred.id;
      updateBuildAvailability();
    });
  }

  function loadStatus() {
    return request("/api/status").then(function (data) {
      setConnection(true, "SERVICIO LOCAL ACTIVO");
      sdkRoot.value = data.sdkRoot || "";
      moduleRoot.value = data.modulesPath || "";
      sdkSummary.textContent = data.validSdk ? "SDK SharpProspero listo" : "Configura la ruta del SDK";
      toolSummary.textContent = data.sdkRoot || "Ruta del SDK no encontrada";
      setToolStatus("dotnet", data.dotnet.available, data.dotnet.version || (data.dotnet.available ? "Instalado" : "No encontrado"));
      var wslReady = data.wsl.available && data.wsl.dotnet10;
      var wslLabel = !data.wsl.available ? "No encontrado" : data.wsl.dotnet10 ? "WSL + .NET 10" : "Falta .NET 10 en WSL";
      setToolStatus("wsl", wslReady, wslLabel);
      setToolStatus("modules", Boolean(data.modulesReady),
        data.modulesReady ? "libc.prx listo" : "Carpeta necesaria");
      var modulesReady = Boolean(data.modulesReady);
      document.getElementById("environment-help").textContent = !wslReady
        ? "Instala .NET 10 dentro de WSL antes de compilar."
        : modulesReady
          ? "Entorno listo; módulos compatibles detectados."
          : "Entorno listo. Configura módulos compatibles si tu aplicación los necesita.";
      var packageChoice = document.getElementById("package-choice");
      var packageRadio = document.querySelector('input[name="output"][value="Package"]');
      packageChoice.hidden = !data.packageSupported;
      packageRadio.disabled = !data.packageSupported;
      document.getElementById("package-help").hidden = Boolean(data.packageSupported);
      if (!data.packageSupported && packageRadio.checked) {
        var folderRadio = document.querySelector('input[name="output"][value="Folder"]');
        folderRadio.checked = true;
        document.querySelectorAll(".output-choice").forEach(function (choice) {
          choice.classList.toggle("selected", choice.contains(folderRadio));
        });
      }
      if (data.sdkRoot) localStorage.setItem("sharpProsperoRoot", data.sdkRoot);
      localStorage.setItem("sharpProsperoModules", data.modulesPath || "");
    });
  }

  function pollJob(jobId) {
    request("/api/jobs/" + encodeURIComponent(jobId)).then(function (job) {
      displayLogs(job.logs || []);
      jobDetail.textContent = job.titleId
        ? "Title ID: " + job.titleId + " · " + (job.detail || "Compilación en curso")
        : (job.detail || "Compilación en curso");
      if (job.state === "running" || job.state === "starting") {
        setJobState("running", "COMPILANDO");
        pollTimer = window.setTimeout(function () { pollJob(jobId); }, 1100);
        return;
      }
      activeJob = null;
      updateBuildAvailability();
      if (job.state === "succeeded") {
        setJobState("success", "COMPLETADO");
        jobDetail.textContent = "Salida: " + job.outputPath +
          (job.titleId ? " · Title ID: " + job.titleId : "");
      } else {
        setJobState("error", "ERROR");
        jobDetail.textContent = job.detail || "La compilación terminó con errores.";
      }
    }).catch(function (error) {
      activeJob = null;
      buildButton.disabled = false;
      setJobState("error", "ERROR");
      jobDetail.textContent = error.message;
      showMessage(error.message, true);
    });
  }

  document.getElementById("toggle-settings").addEventListener("click", function () {
    settingsPanel.hidden = !settingsPanel.hidden;
    if (!settingsPanel.hidden) sdkRoot.focus();
  });

  document.getElementById("save-sdk").addEventListener("click", function () {
    var button = document.getElementById("save-sdk");
    button.disabled = true;
    request("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sdkRoot: sdkRoot.value.trim(), modulesPath: moduleRoot.value.trim() })
    }).then(function (data) {
      localStorage.setItem("sharpProsperoRoot", data.sdkRoot);
      localStorage.setItem("sharpProsperoModules", data.modulesPath || "");
      return loadStatus().then(loadProjects);
    }).then(function () {
      settingsPanel.hidden = true;
      showMessage("Ruta del SDK guardada para esta sesión.", false);
    }).catch(function (error) {
      showMessage(error.message, true);
    }).finally(function () {
      button.disabled = false;
    });
  });

  document.querySelectorAll('input[name="output"]').forEach(function (input) {
    input.addEventListener("change", function () {
      document.querySelectorAll(".output-choice").forEach(function (choice) {
        choice.classList.toggle("selected", choice.contains(input) && input.checked);
      });
    });
  });

  customProject.value = localStorage.getItem("sharpProsperoProject") || "";
  updateBuildAvailability();
  customProject.addEventListener("input", function () {
    localStorage.setItem("sharpProsperoProject", customProject.value);
    updateBuildAvailability();
  });

  document.getElementById("build-form").addEventListener("submit", function (event) {
    event.preventDefault();
    if (activeJob || (!customProject.value.trim() && !projectSelect.value)) return;
    buildButton.disabled = true;
    setJobState("running", "INICIANDO");
    jobDetail.textContent = "Iniciando build-app.ps1…";
    showMessage("Solicitando compilación local…", false);

    request("/api/build", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        project: projectSelect.value,
        projectPath: customProject.value.trim(),
        output: document.querySelector('input[name="output"]:checked').value
      })
    }).then(function (job) {
      activeJob = job.id;
      if (job.titleId) {
        showMessage("Title ID reservado para esta build: " + job.titleId, false);
      }
      pollJob(job.id);
    }).catch(function (error) {
      activeJob = null;
      updateBuildAvailability();
      setJobState("error", "ERROR");
      jobDetail.textContent = error.message;
      showMessage(error.message, true);
    });
  });

  document.getElementById("clear-log").addEventListener("click", function () {
    lastLog = "";
    buildLog.replaceChildren();
    var empty = document.createElement("p");
    empty.className = "log-placeholder";
    empty.textContent = "Registro limpiado.";
    buildLog.appendChild(empty);
  });

  var savedRoot = localStorage.getItem("sharpProsperoRoot");
  loadStatus().then(function () {
    var savedModules = localStorage.getItem("sharpProsperoModules") || "";
    if ((!savedRoot || savedRoot === sdkRoot.value) && savedModules === moduleRoot.value) return;
    if (savedRoot) sdkRoot.value = savedRoot;
    return request("/api/config", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        sdkRoot: savedRoot || sdkRoot.value,
        modulesPath: savedModules
      })
    }).then(function (data) {
      sdkRoot.value = data.sdkRoot;
      moduleRoot.value = data.modulesPath || "";
      localStorage.setItem("sharpProsperoRoot", data.sdkRoot);
      localStorage.setItem("sharpProsperoModules", data.modulesPath || "");
      return loadStatus();
    });
  }).then(loadProjects).catch(function (error) {
    setConnection(false, "SERVICIO LOCAL NO DISPONIBLE");
    sdkSummary.textContent = "No se pudo conectar";
    toolSummary.textContent = error.message;
    showMessage(error.message, true);
  });

  window.addEventListener("beforeunload", function () {
    if (pollTimer) window.clearTimeout(pollTimer);
  });
}());
