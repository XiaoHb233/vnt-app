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
import android.view.WindowManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.ProgressBar;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.FileProvider;

import java.io.File;

/**
 * 原生 WebView Activity - 用于内网访问
 * 提供比 Flutter WebView 更流畅的键盘体验
 */
public class IntranetWebActivity extends AppCompatActivity {
    private static final String TAG = "IntranetWebActivity";
    private static final int FILE_CHOOSER_REQUEST_CODE = 1001;

    public static final String EXTRA_URL = "url";
    public static final String EXTRA_TITLE = "title";
    public static final String EXTRA_SERVER_IP = "server_ip";

    private WebView webView;
    private ProgressBar progressBar;
    private String serverIp;
    private String currentUrl;
    private long lastBackTime = 0;
    private static final long BACK_INTERVAL = 1500; // 1.5秒内双击返回

    private ValueCallback<Uri[]> filePathCallback;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 请求窗口特性
        supportRequestWindowFeature(Window.FEATURE_NO_TITLE);
        setContentView(R.layout.activity_intranet_web);

        // 获取参数
        Intent intent = getIntent();
        String url = intent.getStringExtra(EXTRA_URL);
        String title = intent.getStringExtra(EXTRA_TITLE);
        serverIp = intent.getStringExtra(EXTRA_SERVER_IP);
        currentUrl = url;

        Log.d(TAG, "打开内网页面: " + url);

        // 设置标题栏
        if (getSupportActionBar() != null) {
            getSupportActionBar().setTitle(title != null ? title : "内网访问");
            getSupportActionBar().setDisplayHomeAsUpEnabled(true);
        }

        // 初始化视图
        webView = findViewById(R.id.webView);
        progressBar = findViewById(R.id.progressBar);

        // 配置 WebView
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setCacheMode(WebSettings.LOAD_DEFAULT);
        settings.setUserAgentString("Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36");

        // 启用硬件加速
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        }

        // 设置 WebViewClient
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return false; // 让 WebView 处理所有链接
            }

            @Override
            public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                super.onPageStarted(view, url, favicon);
                progressBar.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                progressBar.setVisibility(View.GONE);
                currentUrl = url;
            }
        });

        // 设置 WebChromeClient 支持文件上传
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                super.onProgressChanged(view, newProgress);
                progressBar.setProgress(newProgress);
            }

            @Override
            public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback,
                                             FileChooserParams fileChooserParams) {
                IntranetWebActivity.this.filePathCallback = filePathCallback;

                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);

                String[] acceptTypes = fileChooserParams.getAcceptTypes();
                if (acceptTypes.length > 0 && !acceptTypes[0].isEmpty()) {
                    intent.setType(acceptTypes[0]);
                } else {
                    intent.setType("*/*");
                }

                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE,
                        fileChooserParams.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE);

                startActivityForResult(Intent.createChooser(intent, "选择文件"), FILE_CHOOSER_REQUEST_CODE);
                return true;
            }
        });

        // 加载页面
        if (url != null) {
            webView.loadUrl(url);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode == FILE_CHOOSER_REQUEST_CODE) {
            if (filePathCallback != null) {
                Uri[] results = null;
                if (resultCode == Activity.RESULT_OK && data != null) {
                    if (data.getClipData() != null) {
                        // 多选
                        int count = data.getClipData().getItemCount();
                        results = new Uri[count];
                        for (int i = 0; i < count; i++) {
                            results[i] = data.getClipData().getItemAt(i).getUri();
                        }
                    } else if (data.getData() != null) {
                        // 单选
                        results = new Uri[]{data.getData()};
                    }
                }
                filePathCallback.onReceiveValue(results);
                filePathCallback = null;
            }
        }
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            handleBackButton();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    /**
     * 处理返回按钮 - 与 HBuilder_app 一致的双重返回逻辑
     */
    private void handleBackButton() {
        long now = System.currentTimeMillis();
        String adminUrl = "http://" + serverIp + "/admin/dashboard.html";

        // 第一次按返回键（1.5秒内）
        if (now - lastBackTime > BACK_INTERVAL) {
            lastBackTime = now;

            // 检查当前是否在 AsynPost 或 QL 页面
            if (currentUrl != null && (currentUrl.contains("/asyn_post.html") ||
                    currentUrl.contains("/ql_scheduler.html"))) {
                // 直接跳转到后台首页
                webView.loadUrl(adminUrl);
                showToast("已返回后台");
            } else if (webView.canGoBack()) {
                // 尝试历史记录返回
                webView.goBack();
                showToast("再按一次返回首页");
            } else {
                // 没有历史记录，关闭 Activity
                finish();
            }
        } else {
            // 第二次按返回键（1.5秒内）：关闭 Activity
            finish();
        }
    }

    private void showToast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    @Override
    public boolean onSupportNavigateUp() {
        finish();
        return true;
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
