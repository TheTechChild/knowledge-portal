FROM ghcr.io/kiwix/kiwix-serve:latest@sha256:9bffd4f940645d4d518f137e87b7865d3d0ef30f6c13fbe4a3b9e747be3cd1ad

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["sh", "-c"]
CMD ["exec kiwix-serve /data/*.zim"]
