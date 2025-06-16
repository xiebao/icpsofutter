child: _videoStarted
    ? _displayMode == 0
        ? AndroidView(
            viewType: 'p2p_video_view',
            creationParams: {
                'decodeMode': _decodeMode,
                'displayMode': _displayMode,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: (int id) {
                setState(() {
                    _platformViewId = id;
                });
            },
          )
        : _textureId != null
            ? Texture(
                textureId: _textureId!,
                filterQuality: FilterQuality.medium,
                fit: BoxFit.contain,
              )
            : Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Text('Texture 初始化中...'),
              )
    : Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Text('请先点击一键启动'),
      ), 