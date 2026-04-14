package top.wherewego.vnt_app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.Window;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ImageButton;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;

/**
 * 原生 WebView Activity - 用于内网访问
 * 提供比 Flutter WebView 更流畅的键盘体验
 */
public class IntranetWebActivity extends Activity {
    private static final String TAG = "IntranetWebActivity";
    private static final int FILE_CHOOSER_REQUEST_CODE = 1001;
    private static final long BACK_INTERVAL = 1500;

    public static final String EXTRA_URL = "url";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_SERVER_IP = "server_ip";

    private WebView webView;
    private ProgressBar progressBar;
    private String serverIp;
    private String currentUrl;
    private long lastBackTime;
    private ValueCallback<Uri[]> filePathCallback;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        setContentView(R.layout.activity_intranet_web);

        Intent intent = getIntent();
        String url = intent.getStringExtra(EXTRA_URL);
        String title = intent.getStringExtra(EXTRA_TITLE);
        serverIp = intent.getStringExtra(EXTRA_SERVER_IP);
        currentUrl = url;

        // 初始化标题栏
        initTitleBar(title);

        webView = findViewById(R.id.webView);
        progressBar = findViewById(R.id.progressBar);

        initWebView(url);
    }

    private void initTitleBar(String title) {
        TextView titleText = findViewById(R.id.titleText);
        ImageButton backButton = findViewById(R.id.backButton);

        if (title != null && !title.isEmpty()) {
            titleText.setText(title);
        }

        backButton.setOnClickListener(v -> finish());
    }

    private void initWebView(String url) {
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setUserAgentString("Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/91.0 Mobile Safari/537.36");

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        }

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                progressBar.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                progressBar.setVisibility(View.GONE);
                currentUrl = url;
            }
        });

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progressBar.setProgress(newProgress);
            }

            @Override
            public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> callback,
                                             WebChromeClient.FileChooserParams params) {
                filePathCallback = callback;
                openFileChooser(params);
                return true;
            }
        });

        if (url != null) {
            webView.loadUrl(url);
        }
    }

    private void openFileChooser(WebChromeClient.FileChooserParams params) {
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        
        String[] acceptTypes = params.getAcceptTypes();
        intent.setType(acceptTypes.length > 0 && !acceptTypes[0].isEmpty() ? acceptTypes[0] : "*/*");
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.getMode() == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE);
        
        startActivityForResult(Intent.createChooser(intent, "选择文件"), FILE_CHOOSER_REQUEST_CODE);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        
        if (requestCode == FILE_CHOOSER_REQUEST_CODE && filePathCallback != null) {
            Uri[] results = null;
            if (resultCode == Activity.RESULT_OK && data != null) {
                if (data.getClipData() != null) {
                    int count = data.getClipData().getItemCount();
                    results = new Uri[count];
                    for (int i = 0; i < count; i++) {
                        results[i] = data.getClipData().getItemAt(i).getUri();
                    }
                } else if (data.getData() != null) {
                    results = new Uri[]{data.getData()};
                }
            }
            filePathCallback.onReceiveValue(results);
            filePathCallback = null;
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            handleBack();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void handleBack() {
        long now = System.currentTimeMillis();
        String adminUrl = "http://" + serverIp + "/admin/dashboard.html";

        if (now - lastBackTime > BACK_INTERVAL) {
            lastBackTime = now;

            if (currentUrl != null && (currentUrl.contains("/asyn_post.html") ||
                    currentUrl.contains("/ql_scheduler.html"))) {
                webView.loadUrl(adminUrl);
                showToast("已返回后台");
            } else if (webView.canGoBack()) {
                webView.goBack();
                showToast("再按一次返回首页");
            } else {
                finish();
            }
        } else {
            finish();
        }
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.stopLoading();
            webView.loadUrl("about:blank");
            webView.clearHistory();
            webView.removeAllViews();
            webView.destroy();
        }
        super.onDestroy();
    }
}
