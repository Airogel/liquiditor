/**
 * Pi Agent Floating Chat Widget
 * Automatically injected via content_for_header
 */

(function () {
  "use strict";

  class PiChatWidget {
    constructor() {
      this.sessionId = this.getOrCreateSessionId();
      this.isOpen = this.getWidgetState();
      this.isStreaming = false;
      this.isUploading = false;
      this.messages = [];

      this.init();
    }

    getWidgetState() {
      try {
        const state = localStorage.getItem("pi_chat_widget_open");
        return state === "true";
      } catch (e) {
        return false;
      }
    }

    saveWidgetState() {
      try {
        localStorage.setItem("pi_chat_widget_open", this.isOpen.toString());
      } catch (e) {
        console.warn("Failed to save widget state:", e);
      }
    }

    getOrCreateSessionId() {
      const stored = localStorage.getItem("pi_chat_session_id");
      if (stored) return stored;

      const newId = `chat-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      localStorage.setItem("pi_chat_session_id", newId);
      return newId;
    }

    init() {
      // Wait for DOM to be ready
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", () => this.render());
      } else {
        this.render();
      }
    }

    render() {
      // Create widget container
      const widget = document.createElement("div");
      widget.className = "pi-chat-widget";
      widget.innerHTML = `
        <button class="pi-chat-toggle" aria-label="Toggle AI Chat">
          <svg class="chat-icon" viewBox="0 0 24 24">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>
            <circle cx="9" cy="10" r="1.5"/>
            <circle cx="15" cy="10" r="1.5"/>
          </svg>
          <svg class="close-icon" viewBox="0 0 24 24">
            <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
          </svg>
        </button>
        
        <div class="pi-chat-panel">
          <div class="pi-chat-header">
            <div>
              <h3>
                <span class="pi-chat-status"></span>
                <span class="pi-chat-title-text">AI Assistant</span>
              </h3>
              <div class="pi-chat-session-info">Session: ${this.sessionId.split("-")[1]}</div>
            </div>
            <button class="pi-chat-new-session-btn" id="piNewSession" aria-label="New session" title="New session">
              <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 20h9"/>
                <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
              </svg>
            </button>
          </div>
          
          <div class="pi-chat-messages" id="piChatMessages">
            <div class="pi-chat-welcome">
              <h4>👋 Hello!</h4>
              <p>I'm your AI coding assistant. Ask me anything about this project, code, or how to use features.</p>
              <p style="margin-top: 0.75rem; font-size: 0.875rem; opacity: 0.8;">💡 <strong>Tip:</strong> After I make changes to files, refresh the page to see updates. This chat will stay open with your conversation history!</p>
              <p style="margin-top: 0.5rem; font-size: 0.875rem; opacity: 0.8;">⏳ <strong>Streaming responses:</strong> Watch the status indicator (thinking → responding → ready) and wait for the response to complete. Refreshing during streaming will interrupt the response.</p>
            </div>
          </div>
          
          <div class="pi-chat-input-area">
            <div class="pi-chat-suggestions">
              <button class="pi-chat-suggestion-btn" data-prompt="What is this page about?">
                About this page
              </button>
              <button class="pi-chat-suggestion-btn" data-prompt="Explain the code structure">
                Code structure
              </button>
              <button class="pi-chat-suggestion-btn" data-prompt="How do I use this feature?">
                How to use
              </button>
            </div>
            
            <div class="pi-chat-upload-preview" id="piUploadPreview" style="display:none;">
              <div class="pi-chat-upload-file-info">
                <svg class="pi-chat-upload-file-icon" viewBox="0 0 24 24"><path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11z"/></svg>
                <span class="pi-chat-upload-filename" id="piUploadFilename"></span>
                <button class="pi-chat-upload-cancel" id="piUploadCancel" aria-label="Cancel upload">&times;</button>
              </div>
              <div class="pi-chat-upload-type-selector">
                <button class="pi-chat-upload-type-btn active" data-type="asset">
                  <svg viewBox="0 0 24 24" width="14" height="14"><path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/></svg>
                  Asset
                </button>
                <button class="pi-chat-upload-type-btn" data-type="inspiration">
                  <svg viewBox="0 0 24 24" width="14" height="14"><path d="M9 21c0 .5.4 1 1 1h4c.6 0 1-.5 1-1v-1H9v1zm3-19C8.1 2 5 5.1 5 9c0 2.4 1.2 4.5 3 5.7V17c0 .5.4 1 1 1h6c.6 0 1-.5 1-1v-2.3c1.8-1.3 3-3.4 3-5.7 0-3.9-3.1-7-7-7z"/></svg>
                  Inspiration
                </button>
              </div>
            </div>

            <div class="pi-chat-input-wrapper">
              <input type="file" id="piFileInput" style="display:none;" />
              <button class="pi-chat-attach-btn" id="piChatAttach" aria-label="Attach file">
                <svg viewBox="0 0 24 24">
                  <path d="M16.5 6v11.5c0 2.21-1.79 4-4 4s-4-1.79-4-4V5c0-1.38 1.12-2.5 2.5-2.5s2.5 1.12 2.5 2.5v10.5c0 .55-.45 1-1 1s-1-.45-1-1V6H10v9.5c0 1.38 1.12 2.5 2.5 2.5s2.5-1.12 2.5-2.5V5c0-2.21-1.79-4-4-4S7 2.79 7 5v12.5c0 3.04 2.46 5.5 5.5 5.5s5.5-2.46 5.5-5.5V6h-1.5z"/>
                </svg>
              </button>
              <textarea 
                class="pi-chat-input" 
                id="piChatInput"
                placeholder="Ask me anything..."
                rows="1"
              ></textarea>
              <button class="pi-chat-send-btn" id="piChatSend" aria-label="Send message">
                <svg viewBox="0 0 24 24">
                  <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/>
                </svg>
              </button>
            </div>
          </div>
        </div>
      `;

      document.body.appendChild(widget);

      // Cache DOM references
      this.toggleBtn = widget.querySelector(".pi-chat-toggle");
      this.panel = widget.querySelector(".pi-chat-panel");
      this.messagesContainer = widget.querySelector("#piChatMessages");
      this.input = widget.querySelector("#piChatInput");
      this.sendBtn = widget.querySelector("#piChatSend");
      this.statusIndicator = widget.querySelector(".pi-chat-status");
      this.headerTitle = widget.querySelector(".pi-chat-header h3");
      this.attachBtn = widget.querySelector("#piChatAttach");
      this.fileInput = widget.querySelector("#piFileInput");
      this.uploadPreview = widget.querySelector("#piUploadPreview");
      this.uploadFilename = widget.querySelector("#piUploadFilename");
      this.uploadCancel = widget.querySelector("#piUploadCancel");
      this.uploadTypeBtns = widget.querySelectorAll(".pi-chat-upload-type-btn");
      this.newSessionBtn = widget.querySelector("#piNewSession");
      this.pendingFile = null;
      this.uploadType = "asset";

      // Bind events
      this.toggleBtn.addEventListener("click", () => this.toggle());
      this.newSessionBtn.addEventListener("click", () => this.newSession());
      this.sendBtn.addEventListener("click", () => this.sendMessage());
      this.input.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          this.sendMessage();
        }
      });

      // Auto-resize textarea
      this.input.addEventListener("input", () => this.autoResizeInput());

      // File upload events
      this.attachBtn.addEventListener("click", () => this.fileInput.click());
      this.fileInput.addEventListener("change", (e) =>
        this.handleFileSelect(e),
      );
      this.uploadCancel.addEventListener("click", () => this.cancelUpload());
      this.uploadTypeBtns.forEach((btn) => {
        btn.addEventListener("click", () => {
          this.uploadTypeBtns.forEach((b) => b.classList.remove("active"));
          btn.classList.add("active");
          this.uploadType = btn.dataset.type;
        });
      });

      // Drag and drop on the chat panel
      this.panel.addEventListener("dragover", (e) => {
        e.preventDefault();
        this.panel.classList.add("drag-over");
      });
      this.panel.addEventListener("dragleave", (e) => {
        e.preventDefault();
        this.panel.classList.remove("drag-over");
      });
      this.panel.addEventListener("drop", (e) => {
        e.preventDefault();
        this.panel.classList.remove("drag-over");
        if (e.dataTransfer.files.length > 0) {
          this.showUploadPreview(e.dataTransfer.files[0]);
        }
      });

      // Suggestion buttons
      widget.querySelectorAll(".pi-chat-suggestion-btn").forEach((btn) => {
        btn.addEventListener("click", () => {
          const prompt = btn.dataset.prompt;
          this.input.value = prompt;
          this.sendMessage();
        });
      });

      // Load previous messages from localStorage
      this.loadMessages();

      // Restore widget state (open/closed)
      if (this.isOpen) {
        this.toggleBtn.classList.add("active");
        this.panel.classList.add("active");
      }
    }

    toggle() {
      this.isOpen = !this.isOpen;
      this.toggleBtn.classList.toggle("active", this.isOpen);
      this.panel.classList.toggle("active", this.isOpen);
      this.saveWidgetState();

      if (this.isOpen) {
        this.input.focus();
      }
    }

    newSession() {
      if (this.isStreaming || this.isUploading) return;

      // Generate new session ID
      this.sessionId = `chat-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      localStorage.setItem("pi_chat_session_id", this.sessionId);

      // Clear messages
      this.messages = [];
      this.saveMessages();

      // Reset messages container with welcome screen
      this.messagesContainer.innerHTML = `
        <div class="pi-chat-welcome">
          <h4>👋 Hello!</h4>
          <p>I'm your AI coding assistant. Ask me anything about this project, code, or how to use features.</p>
          <p style="margin-top: 0.75rem; font-size: 0.875rem; opacity: 0.8;">💡 <strong>Tip:</strong> After I make changes to files, refresh the page to see updates. This chat will stay open with your conversation history!</p>
          <p style="margin-top: 0.5rem; font-size: 0.875rem; opacity: 0.8;">⏳ <strong>Streaming responses:</strong> Watch the status indicator (thinking → responding → ready) and wait for the response to complete. Refreshing during streaming will interrupt the response.</p>
        </div>
      `;

      // Update session info display
      const sessionInfo = this.panel.querySelector(".pi-chat-session-info");
      if (sessionInfo) {
        sessionInfo.textContent = `Session: ${this.sessionId.split("-")[1]}`;
      }

      this.input.focus();
    }

    autoResizeInput() {
      this.input.style.height = "auto";
      this.input.style.height = Math.min(this.input.scrollHeight, 100) + "px";
    }

    addMessage(role, content, streaming = false) {
      const message = { role, content, timestamp: Date.now() };
      this.messages.push(message);

      // Remove welcome message on first user message
      if (role === "user" && this.messages.length === 1) {
        const welcome =
          this.messagesContainer.querySelector(".pi-chat-welcome");
        if (welcome) welcome.remove();
      }

      const messageEl = document.createElement("div");
      messageEl.className = `pi-chat-message ${role}`;
      if (streaming) messageEl.classList.add("streaming");

      messageEl.innerHTML = `
        <div class="pi-chat-message-role">${role}</div>
        <div class="pi-chat-message-content">${this.escapeHtml(content)}</div>
      `;

      this.messagesContainer.appendChild(messageEl);
      this.scrollToBottom();

      // Don't save streaming messages to localStorage yet (they're empty)
      if (!streaming) {
        this.saveMessages();
      }

      return messageEl;
    }

    updateMessage(messageEl, content) {
      const contentEl = messageEl.querySelector(".pi-chat-message-content");
      contentEl.textContent = content;
      this.scrollToBottom();
    }

    scrollToBottom() {
      this.messagesContainer.scrollTop = this.messagesContainer.scrollHeight;
    }

    async sendMessage() {
      const prompt = this.input.value.trim();
      const hasPendingFile = !!this.pendingFile;

      // Need either a prompt or a file
      if (!prompt && !hasPendingFile) return;
      if (this.isStreaming || this.isUploading) return;

      // Handle file upload first if there's a pending file
      if (hasPendingFile) {
        const uploadResult = await this.uploadFile();

        // If there's also a prompt, send it referencing the uploaded file
        if (prompt && uploadResult) {
          const fileRef =
            uploadResult.type === "inspiration"
              ? `I just uploaded an inspiration file "${uploadResult.filename}". `
              : `I just uploaded an asset file "${uploadResult.filename}" (at ${uploadResult.path}). `;
          this.input.value = fileRef + prompt;
        } else if (!prompt) {
          // No prompt, just the upload - done
          return;
        }
      }

      const finalPrompt = this.input.value.trim() || prompt;
      if (!finalPrompt) return;

      // Add user message
      this.addMessage("user", finalPrompt);
      this.input.value = "";
      this.input.style.height = "auto";

      // Disable input and update status
      this.isStreaming = true;
      window.__piChatStreaming = true;
      this.sendBtn.disabled = true;
      this.input.disabled = true;
      this.updateStatus("thinking");

      // Show typing indicator
      const typingIndicator = this.addTypingIndicator();

      try {
        // Use streaming endpoint
        await this.streamResponse(finalPrompt, typingIndicator);
      } catch (error) {
        console.error("Pi chat error:", error);
        this.addMessage(
          "error",
          `Error: ${error.message}\n\nPlease wait for responses to complete before refreshing. The assistant is thinking and streaming the response in real-time.`,
        );
      } finally {
        // Remove typing indicator if still present
        if (typingIndicator && typingIndicator.parentNode) {
          typingIndicator.remove();
        }

        this.isStreaming = false;
        window.__piChatStreaming = false;
        this.sendBtn.disabled = false;
        this.input.disabled = false;
        this.updateStatus("ready");
        this.input.focus();

        // If live reload was deferred during streaming, execute it now
        if (window.__piChatPendingReload) {
          window.__piChatPendingReload = false;
          location.reload();
        }
      }
    }

    updateStatus(state) {
      if (state === "thinking") {
        this.statusIndicator.style.background = "#fbbf24";
        this.statusIndicator.style.animation = "pulse 0.8s infinite";
        const titleText = this.headerTitle.querySelector(".pi-chat-title-text");
        if (titleText) {
          titleText.textContent = "AI Assistant (thinking...)";
        }
      } else if (state === "streaming") {
        this.statusIndicator.style.background = "#3b82f6";
        this.statusIndicator.style.animation = "pulse 0.8s infinite";
        const titleText = this.headerTitle.querySelector(".pi-chat-title-text");
        if (titleText) {
          titleText.textContent = "AI Assistant (responding...)";
        }
      } else {
        this.statusIndicator.style.background = "#4ade80";
        this.statusIndicator.style.animation = "pulse 2s infinite";
        const titleText = this.headerTitle.querySelector(".pi-chat-title-text");
        if (titleText) {
          titleText.textContent = "AI Assistant";
        }
      }
    }

    addTypingIndicator() {
      const indicator = document.createElement("div");
      indicator.className = "pi-chat-message assistant typing-indicator";
      indicator.innerHTML = `
        <div class="pi-chat-message-role">assistant</div>
        <div class="pi-chat-message-content">
          <div class="typing-dots">
            <span></span>
            <span></span>
            <span></span>
          </div>
        </div>
      `;
      this.messagesContainer.appendChild(indicator);
      this.scrollToBottom();
      return indicator;
    }

    getPageContext() {
      // Get content_path from meta tag (preferred source)
      const contentPathMeta = document.querySelector(
        'meta[name="content_path"]',
      );
      const contentPath = contentPathMeta
        ? contentPathMeta.getAttribute("content")
        : null;

      return {
        content_path: contentPath,
        pathname: window.location.pathname,
        full_url: window.location.href,
        page_title: document.title,
      };
    }

    async streamResponse(prompt, typingIndicator) {
      const context = this.getPageContext();

      // Build URL with context parameters
      const params = new URLSearchParams({
        prompt: prompt,
        session_id: this.sessionId,
      });

      // Add context if available
      if (context.content_path) {
        params.append("content_path", context.content_path);
      }
      if (context.pathname) {
        params.append("pathname", context.pathname);
      }
      if (context.full_url) {
        params.append("full_url", context.full_url);
      }
      if (context.page_title) {
        params.append("page_title", context.page_title);
      }

      const url = `/api/pi/stream?${params.toString()}`;

      return new Promise((resolve, reject) => {
        const eventSource = new EventSource(url);
        let assistantMessageEl = null;
        let fullText = "";
        let hasStarted = false;

        eventSource.addEventListener("message", (e) => {
          // Create assistant message on first chunk
          if (!assistantMessageEl) {
            // Remove typing indicator before showing response
            if (typingIndicator && typingIndicator.parentNode) {
              typingIndicator.remove();
            }

            assistantMessageEl = this.addMessage("assistant", "", true);
            hasStarted = true;
            this.updateStatus("streaming");
          }

          // Unescape the chunk
          const chunk = e.data
            .replace(/\\n/g, "\n")
            .replace(/\\"/g, '"')
            .replace(/\\\\/g, "\\");

          fullText += chunk;
          this.updateMessage(assistantMessageEl, fullText);
        });

        eventSource.addEventListener("start", (e) => {
          hasStarted = true;
        });

        eventSource.addEventListener("done", () => {
          if (assistantMessageEl) {
            assistantMessageEl.classList.remove("streaming");
            // Update the last message in storage
            this.messages[this.messages.length - 1].content = fullText;
            this.saveMessages();
          }
          eventSource.close();
          resolve();
        });

        eventSource.addEventListener("error", (e) => {
          console.error("Stream error:", e);
          eventSource.close();

          if (!hasStarted) {
            reject(
              new Error("Failed to start stream. The server may be busy."),
            );
          } else {
            // If we had started streaming, just resolve - we have partial content
            if (assistantMessageEl) {
              assistantMessageEl.classList.remove("streaming");
              this.messages[this.messages.length - 1].content =
                fullText + "\n\n[Connection interrupted]";
              this.saveMessages();
            }
            resolve();
          }
        });
      });
    }

    escapeHtml(text) {
      const div = document.createElement("div");
      div.textContent = text;
      return div.innerHTML;
    }

    handleFileSelect(e) {
      const file = e.target.files[0];
      if (!file) return;
      this.showUploadPreview(file);
    }

    showUploadPreview(file) {
      this.pendingFile = file;
      this.uploadFilename.textContent = file.name;
      this.uploadPreview.style.display = "block";

      // Auto-select type based on file extension
      const ext = file.name.split(".").pop().toLowerCase();
      const assetExts = [
        "css",
        "js",
        "svg",
        "ico",
        "woff",
        "woff2",
        "ttf",
        "eot",
      ];
      if (assetExts.includes(ext)) {
        this.selectUploadType("asset");
      } else {
        // Images could be either; default to inspiration for non-web files
        const imageExts = ["jpg", "jpeg", "png", "gif", "webp"];
        const docExts = [
          "pdf",
          "txt",
          "md",
          "doc",
          "docx",
          "sketch",
          "fig",
          "psd",
          "ai",
          "xd",
        ];
        if (docExts.includes(ext)) {
          this.selectUploadType("inspiration");
        }
        // Otherwise keep current selection
      }
    }

    selectUploadType(type) {
      this.uploadType = type;
      this.uploadTypeBtns.forEach((btn) => {
        btn.classList.toggle("active", btn.dataset.type === type);
      });
    }

    cancelUpload() {
      this.pendingFile = null;
      this.uploadPreview.style.display = "none";
      this.fileInput.value = "";
    }

    async uploadFile() {
      if (!this.pendingFile || this.isUploading) return null;

      const file = this.pendingFile;
      const type = this.uploadType;
      this.isUploading = true;

      // Show upload message in chat
      const label = type === "asset" ? "Asset" : "Inspiration";
      this.addMessage("user", `[Uploading ${label}: ${file.name}]`);
      this.cancelUpload();

      try {
        const formData = new FormData();
        formData.append("file", file);
        formData.append("type", type);
        const response = await window.fetch("/api/uploads", {
          method: "POST",
          body: formData,
        });

        const result = await response.json();

        if (result.success) {
          const msg =
            type === "asset"
              ? `Uploaded asset: ${result.filename} (available at ${result.path})`
              : `Uploaded inspiration: ${result.filename} (available to AI assistant)`;
          this.addMessage("system", msg);
          return result;
        } else {
          this.addMessage(
            "error",
            `Upload failed: ${result.error || "Unknown error"}`,
          );
          return null;
        }
      } catch (error) {
        console.error("[upload] caught error:", error);
        console.error("[upload] error stack:", error.stack);
        this.addMessage("error", `Upload failed: ${error.message}`);
        return null;
      } finally {
        this.isUploading = false;
      }
    }

    saveMessages() {
      // Keep only last 50 messages to avoid localStorage limits
      const recentMessages = this.messages.slice(-50);
      try {
        localStorage.setItem(
          `pi_chat_messages_${this.sessionId}`,
          JSON.stringify(recentMessages),
        );
      } catch (e) {
        console.warn("Failed to save messages to localStorage:", e);
      }
    }

    loadMessages() {
      try {
        const stored = localStorage.getItem(
          `pi_chat_messages_${this.sessionId}`,
        );
        if (!stored) return;

        this.messages = JSON.parse(stored);

        if (this.messages.length > 0) {
          // Remove welcome message
          const welcome =
            this.messagesContainer.querySelector(".pi-chat-welcome");
          if (welcome) welcome.remove();

          // Render stored messages
          this.messages.forEach((msg) => {
            const messageEl = document.createElement("div");
            messageEl.className = `pi-chat-message ${msg.role}`;
            messageEl.innerHTML = `
              <div class="pi-chat-message-role">${msg.role}</div>
              <div class="pi-chat-message-content">${this.escapeHtml(msg.content)}</div>
            `;
            this.messagesContainer.appendChild(messageEl);
          });

          this.scrollToBottom();
        }
      } catch (e) {
        console.warn("Failed to load messages from localStorage:", e);
      }
    }
  }

  // Initialize widget
  new PiChatWidget();
})();
